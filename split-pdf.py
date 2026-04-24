#!/usr/bin/env python3
"""
split-pdf.py — Split a PDF into page-range parts for Azure Content Understanding indexing.

The Content Understanding skill has a 300-page limit per document. This script splits
large PDFs into overlapping parts so the full document can be indexed without truncation.

Each output file is named:  <stem>_part<N>_p<start>-<end>.pdf
  e.g.  pg_part1_p001-300.pdf
        pg_part2_p281-580.pdf   (20-page overlap with part 1)
        pg_part3_p561-590.pdf

Usage:
    # Split a single file (default: 300 pages per part, 20-page overlap)
    python split-pdf.py pg.pdf

    # Custom page size and overlap
    python split-pdf.py pg.pdf --max-pages 250 --overlap 30

    # Split and upload to Azure Blob Storage
    python split-pdf.py pg.pdf --upload --storage-account sta3zbhnpz6unnk --container pdfs

    # Upload only (skip splitting, just upload existing files matching a pattern)
    python split-pdf.py --upload-only pg_part*.pdf --storage-account sta3zbhnpz6unnk --container pdfs

    # Split all PDFs in a folder
    python split-pdf.py --folder ./docs --upload --storage-account sta3zbhnpz6unnk --container pdfs

Requirements:
    pip install pikepdf azure-storage-blob azure-identity
"""

import argparse
import glob
import shutil
import sys
from pathlib import Path


def split_pdf(input_path: Path, output_dir: Path, max_pages: int, overlap: int) -> list[Path]:
    """Split a PDF into parts of at most max_pages with overlap pages between consecutive parts.
    PDFs within the page limit are copied as-is to the output directory.

    Returns the list of output file paths created.
    """
    try:
        import pikepdf
    except ImportError:
        print("ERROR: pikepdf is not installed. Run: pip install pikepdf", file=sys.stderr)
        sys.exit(1)

    src = pikepdf.open(str(input_path))
    total_pages = len(src.pages)

    output_dir.mkdir(parents=True, exist_ok=True)

    if total_pages <= max_pages:
        # Copy the file as-is to the output directory
        out_path = output_dir / input_path.name
        shutil.copy2(input_path, out_path)
        print(f"  ✅ {input_path.name}: {total_pages} pages — copied as-is (≤ {max_pages})")
        src.close()
        return [out_path]

    stem = input_path.stem
    output_files: list[Path] = []

    part = 1
    start = 0  # 0-based index

    while start < total_pages:
        end = min(start + max_pages, total_pages)  # exclusive

        dst = pikepdf.new()
        dst.pages.extend(src.pages[start:end])

        # Human-readable 1-based page numbers in the filename
        page_from = start + 1
        page_to = end
        out_name = f"{stem}_part{part}_p{page_from:04d}-{page_to:04d}.pdf"
        out_path = output_dir / out_name

        dst.save(str(out_path))
        dst.close()

        print(f"  ✅ Part {part}: pages {page_from}–{page_to} → {out_path.name}")
        output_files.append(out_path)

        # Advance start: next chunk begins (max_pages - overlap) pages after current start
        advance = max_pages - overlap
        start += advance
        part += 1

    src.close()
    print(f"  📄 {input_path.name}: {total_pages} pages split into {len(output_files)} parts")
    return output_files


def upload_to_blob(files: list[Path], storage_account: str, container: str) -> None:
    """Upload files to Azure Blob Storage using DefaultAzureCredential (no keys needed)."""
    try:
        from azure.identity import DefaultAzureCredential
        from azure.storage.blob import BlobServiceClient
    except ImportError:
        print("ERROR: azure packages not installed. Run: pip install azure-storage-blob azure-identity", file=sys.stderr)
        sys.exit(1)

    account_url = f"https://{storage_account}.blob.core.windows.net"
    credential = DefaultAzureCredential()
    client = BlobServiceClient(account_url=account_url, credential=credential)
    container_client = client.get_container_client(container)

    for path in files:
        blob_name = path.name
        print(f"  ⬆️  Uploading {blob_name} ...", end=" ", flush=True)
        with open(path, "rb") as data:
            container_client.upload_blob(blob_name, data, overwrite=True)
        print("✅")

    print(f"\n  {len(files)} file(s) uploaded to {account_url}/{container}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Split PDFs into ≤300-page parts for Azure Content Understanding indexing.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("inputs", nargs="*", help="PDF file(s) or glob pattern(s) to split")
    parser.add_argument("--folder", help="Process all PDFs in this folder")
    parser.add_argument("--output-dir", default="./split_output", help="Directory for split files (default: ./split_output)")
    parser.add_argument("--max-pages", type=int, default=300, help="Max pages per part (default: 300, Content Understanding limit)")
    parser.add_argument("--overlap", type=int, default=20, help="Page overlap between consecutive parts (default: 20)")
    parser.add_argument("--upload", action="store_true", help="Upload split parts to Azure Blob Storage")
    parser.add_argument("--upload-only", nargs="+", metavar="FILE", help="Skip splitting; upload these files directly")
    parser.add_argument("--storage-account", help="Azure Storage account name (required if --upload)")
    parser.add_argument("--container", default="pdfs", help="Blob container name (default: pdfs)")
    args = parser.parse_args()

    if args.overlap >= args.max_pages:
        print("ERROR: --overlap must be less than --max-pages", file=sys.stderr)
        sys.exit(1)

    # ── Collect input files ────────────────────────────────────────────────────

    if args.upload_only:
        files_to_upload: list[Path] = []
        for pattern in args.upload_only:
            matched = [Path(p) for p in glob.glob(pattern)]
            if not matched:
                print(f"WARNING: no files matched '{pattern}'")
            files_to_upload.extend(matched)
        if not files_to_upload:
            print("No files to upload.")
            sys.exit(0)
        if not args.storage_account:
            print("ERROR: --storage-account is required with --upload-only", file=sys.stderr)
            sys.exit(1)
        print(f"\nUploading {len(files_to_upload)} file(s)...")
        upload_to_blob(files_to_upload, args.storage_account, args.container)
        return

    input_paths: list[Path] = []
    if args.folder:
        input_paths.extend(sorted(Path(args.folder).glob("*.pdf")))
    for pattern in (args.inputs or []):
        matched = [Path(p) for p in glob.glob(pattern)]
        if not matched and Path(pattern).exists():
            matched = [Path(pattern)]
        if not matched:
            print(f"WARNING: no files matched '{pattern}'")
        input_paths.extend(matched)

    if not input_paths:
        parser.print_help()
        sys.exit(0)

    output_dir = Path(args.output_dir)
    all_output_files: list[Path] = []

    print(f"\nSplitting PDFs (max {args.max_pages} pages/part, {args.overlap}-page overlap)...")
    print(f"Output directory: {output_dir.resolve()}\n")

    for pdf_path in input_paths:
        if not pdf_path.exists():
            print(f"WARNING: {pdf_path} not found — skipping")
            continue
        print(f"Processing: {pdf_path}")
        parts = split_pdf(pdf_path, output_dir, args.max_pages, args.overlap)
        all_output_files.extend(parts)

    if not all_output_files:
        print("\nNo files processed.")
        return

    print(f"\nTotal files in output directory: {len(all_output_files)}")

    if args.upload:
        if not args.storage_account:
            print("ERROR: --storage-account is required with --upload", file=sys.stderr)
            sys.exit(1)
        print(f"\nUploading to {args.storage_account}/{args.container}...")
        upload_to_blob(all_output_files, args.storage_account, args.container)

    print("\nDone.")
    print("\nNext steps:")
    print("  1. Trigger indexer:")
    print("     az rest --method POST \\")
    print("       --url 'https://<search>.search.windows.net/indexers/pdf-indexer/run?api-version=2025-11-01-Preview' \\")
    print("       --resource https://search.azure.com/")


if __name__ == "__main__":
    main()
