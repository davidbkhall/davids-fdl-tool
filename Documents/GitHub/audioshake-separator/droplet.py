#!/usr/bin/env python3
"""
Drag-and-Drop handler for Voice Separator
Receives files dropped onto the macOS app
"""

import sys
import subprocess
from pathlib import Path

from dotenv import load_dotenv
from rich.console import Console

# Find the script directory (for .env file)
SCRIPT_DIR = Path(__file__).parent.resolve()
load_dotenv(SCRIPT_DIR / ".env")

console = Console()


def main():
    if len(sys.argv) < 2:
        console.print("[yellow]Drop audio files onto this app to separate vocals.[/yellow]")
        console.print("\nOr run from command line:")
        console.print("  python separator.py <file>")
        console.print("  python batch.py <directory>")
        input("\nPress Enter to close...")
        return
    
    # Get dropped files
    dropped_files = [Path(f) for f in sys.argv[1:]]
    
    # Filter to valid files and directories
    valid_items = [f for f in dropped_files if f.exists()]
    
    if not valid_items:
        console.print("[red]❌ No valid files or folders found.[/red]")
        input("\nPress Enter to close...")
        return
    
    console.print(f"\n[bold cyan]🎧 Audioshake Voice Separator[/bold cyan]\n")
    console.print(f"Received {len(valid_items)} item(s):\n")
    
    for item in valid_items:
        console.print(f"   • {item.name}")
    
    # Determine output directory (same as first input's parent)
    output_dir = valid_items[0].parent / "separated_vocals"
    console.print(f"\n[blue]Output folder:[/blue] {output_dir}\n")
    
    # Process based on what was dropped
    audio_files = []
    directories = []
    
    for item in valid_items:
        if item.is_dir():
            directories.append(item)
        elif item.is_file():
            audio_files.append(item)
    
    # Import here to avoid circular imports
    from separator import check_api_key, separate_file, is_valid_audio_file
    from batch import batch_process
    
    if not check_api_key():
        input("\nPress Enter to close...")
        return
    
    # Process directories with batch
    for directory in directories:
        console.print(f"\n[blue]Processing folder:[/blue] {directory.name}")
        batch_process(directory, output_dir, recursive=True, max_workers=2)
    
    # Process individual files
    if audio_files:
        console.print(f"\n[blue]Processing {len(audio_files)} file(s)...[/blue]\n")
        
        for audio_file in audio_files:
            if is_valid_audio_file(audio_file):
                console.print(f"[blue]→[/blue] {audio_file.name}")
                success = separate_file(audio_file, output_dir, quiet=False)
                if success:
                    console.print(f"[green]✅ Complete:[/green] {audio_file.name}\n")
                else:
                    console.print(f"[red]❌ Failed:[/red] {audio_file.name}\n")
            else:
                console.print(f"[yellow]⚠️ Skipped (unsupported):[/yellow] {audio_file.name}")
    
    console.print(f"\n[bold green]🎉 All done![/bold green]")
    console.print(f"[blue]Files saved to:[/blue] {output_dir}\n")
    
    # Open output folder in Finder
    try:
        subprocess.run(["open", str(output_dir)], check=False)
    except Exception:
        pass
    
    input("Press Enter to close...")


if __name__ == "__main__":
    main()