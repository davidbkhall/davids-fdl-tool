#!/usr/bin/env python3
"""
Batch Voice Separation using Audioshake API
Process multiple audio files at once
"""

import argparse
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from dotenv import load_dotenv
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, TaskID, BarColumn, TextColumn, TimeElapsedColumn

from separator import check_api_key, separate_file, is_valid_audio_file, VALID_EXTENSIONS

load_dotenv()

console = Console()


def find_audio_files(input_path: Path, recursive: bool = False) -> list[Path]:
    """Find all audio files in directory."""
    if input_path.is_file():
        return [input_path] if is_valid_audio_file(input_path) else []
    
    if recursive:
        files = []
        for ext in VALID_EXTENSIONS:
            files.extend(input_path.rglob(f"*{ext}"))
            files.extend(input_path.rglob(f"*{ext.upper()}"))
        return sorted(set(files))
    else:
        files = []
        for ext in VALID_EXTENSIONS:
            files.extend(input_path.glob(f"*{ext}"))
            files.extend(input_path.glob(f"*{ext.upper()}"))
        return sorted(set(files))


def process_file(file_path: Path, output_dir: Path) -> tuple[Path, bool, str]:
    """Process a single file. Returns (path, success, message)."""
    try:
        success = separate_file(file_path, output_dir, quiet=True)
        if success:
            return (file_path, True, "✅ Success")
        else:
            return (file_path, False, "❌ Failed")
    except Exception as e:
        return (file_path, False, f"❌ Error: {str(e)[:50]}")


def batch_process(
    input_path: Path,
    output_dir: Path,
    recursive: bool = False,
    max_workers: int = 2,
):
    """Process multiple files with progress tracking."""
    console.print("\n[bold cyan]🎧 Audioshake Batch Voice Separator[/bold cyan]\n")
    
    if not check_api_key():
        sys.exit(1)
    
    # Find files
    console.print(f"[blue]🔍 Scanning for audio files...[/blue]")
    files = find_audio_files(input_path, recursive)
    
    if not files:
        console.print("[yellow]⚠️ No audio files found.[/yellow]")
        console.print(f"   Supported formats: {', '.join(VALID_EXTENSIONS)}")
        sys.exit(1)
    
    console.print(f"[green]✅ Found {len(files)} audio file(s)[/green]\n")
    
    # Show files to process
    for f in files[:10]:
        console.print(f"   • {f.name}")
    if len(files) > 10:
        console.print(f"   ... and {len(files) - 10} more\n")
    
    # Confirm
    console.print(f"\n[yellow]Output directory:[/yellow] {output_dir}")
    console.print(f"[yellow]Parallel jobs:[/yellow] {max_workers}\n")
    
    # Process files
    results: list[tuple[Path, bool, str]] = []
    
    with Progress(
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        TextColumn("•"),
        TimeElapsedColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Processing files...", total=len(files))
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(process_file, f, output_dir): f
                for f in files
            }
            
            for future in as_completed(futures):
                result = future.result()
                results.append(result)
                progress.advance(task)
                
                # Show inline status
                file_path, success, message = result
                if success:
                    progress.console.print(f"   [green]✅[/green] {file_path.name}")
                else:
                    progress.console.print(f"   [red]❌[/red] {file_path.name}: {message}")
    
    # Summary
    console.print("\n" + "─" * 50)
    console.print("[bold]Summary[/bold]\n")
    
    successful = sum(1 for _, success, _ in results if success)
    failed = len(results) - successful
    
    table = Table(show_header=False, box=None)
    table.add_row("✅ Successful:", f"[green]{successful}[/green]")
    table.add_row("❌ Failed:", f"[red]{failed}[/red]" if failed else "0")
    table.add_row("📁 Output:", str(output_dir))
    console.print(table)
    
    # Show failures
    if failed > 0:
        console.print("\n[red]Failed files:[/red]")
        for file_path, success, message in results:
            if not success:
                console.print(f"   • {file_path.name}: {message}")
    
    console.print()


def main():
    parser = argparse.ArgumentParser(
        description="Batch extract vocals from multiple audio files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s ./music
  %(prog)s ./music -o ./vocals -r
  %(prog)s ./songs --workers 4
  %(prog)s song1.mp3 song2.mp3 song3.mp3
        """,
    )
    
    parser.add_argument(
        "input",
        type=Path,
        nargs="+",
        help="Input directory or audio files",
    )
    
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("./output"),
        help="Output directory (default: ./output)",
    )
    
    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Search subdirectories recursively",
    )
    
    parser.add_argument(
        "-w", "--workers",
        type=int,
        default=2,
        help="Number of parallel jobs (default: 2)",
    )
    
    args = parser.parse_args()
    
    # Handle multiple input files
    if len(args.input) > 1:
        # Multiple files specified directly
        for input_file in args.input:
            if input_file.is_file():
                batch_process(input_file.parent, args.output, False, args.workers)
    else:
        batch_process(args.input[0], args.output, args.recursive, args.workers)


if __name__ == "__main__":
    main()