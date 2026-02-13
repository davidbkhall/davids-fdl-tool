#!/usr/bin/env python3
"""
Voice Separation CLI using Audioshake API
Extracts vocals from audio files
"""

import argparse
import os
import sys
import time
from pathlib import Path
from typing import Optional

import requests
from dotenv import load_dotenv
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

load_dotenv()

console = Console()

API_BASE_URL = "https://groovy.audioshake.ai"
API_KEY = os.getenv("AUDIOSHAKE_API_KEY")

VALID_EXTENSIONS = {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".aac", ".wma"}


def check_api_key() -> bool:
    """Verify API key is configured."""
    if not API_KEY:
        console.print("\n[red]❌ AUDIOSHAKE_API_KEY not found![/red]\n")
        console.print("To get started:")
        console.print("  1. Get your API key from [link]https://www.audioshake.ai[/link]")
        console.print("  2. Copy .env.example to .env")
        console.print("  3. Add your API key to the .env file\n")
        return False
    return True


def get_headers() -> dict:
    """Return headers for API requests."""
    return {"Authorization": f"Bearer {API_KEY}"}


def is_valid_audio_file(file_path: Path) -> bool:
    """Check if file is a supported audio format."""
    return file_path.suffix.lower() in VALID_EXTENSIONS


def upload_file(file_path: Path, quiet: bool = False) -> Optional[str]:
    """Upload audio file and return asset ID."""
    if not quiet:
        console.print(f"[blue]📤 Uploading:[/blue] {file_path.name}")
    
    url = f"{API_BASE_URL}/upload"
    
    try:
        with open(file_path, "rb") as f:
            files = {"file": (file_path.name, f)}
            response = requests.post(url, headers=get_headers(), files=files, timeout=300)
        
        if response.status_code != 200:
            console.print(f"[red]❌ Upload failed ({response.status_code}):[/red] {response.text}")
            return None
        
        asset_id = response.json().get("id")
        if not quiet:
            console.print(f"[green]✅ Uploaded[/green] (Asset ID: {asset_id})")
        return asset_id
    
    except requests.exceptions.RequestException as e:
        console.print(f"[red]❌ Upload error:[/red] {e}")
        return None


def create_job(asset_id: str, quiet: bool = False) -> Optional[str]:
    """Create vocal separation job and return job ID."""
    if not quiet:
        console.print("[blue]🎵 Starting vocal separation...[/blue]")
    
    url = f"{API_BASE_URL}/job"
    payload = {
        "assetId": asset_id,
        "format": "vocals",
        "name": "vocal-separation",
    }
    
    try:
        response = requests.post(url, headers=get_headers(), json=payload, timeout=60)
        
        if response.status_code not in [200, 201]:
            console.print(f"[red]❌ Job creation failed ({response.status_code}):[/red] {response.text}")
            return None
        
        job_id = response.json().get("id")
        if not quiet:
            console.print(f"[green]✅ Job started[/green] (Job ID: {job_id})")
        return job_id
    
    except requests.exceptions.RequestException as e:
        console.print(f"[red]❌ Job creation error:[/red] {e}")
        return None


def wait_for_completion(job_id: str, poll_interval: int = 5, quiet: bool = False) -> Optional[dict]:
    """Poll until job completes."""
    url = f"{API_BASE_URL}/job/{job_id}"
    
    if quiet:
        while True:
            try:
                response = requests.get(url, headers=get_headers(), timeout=30)
                if response.status_code != 200:
                    return None
                
                data = response.json()
                status = data.get("status", "unknown")
                
                if status == "completed":
                    return data
                elif status == "failed":
                    return None
                
                time.sleep(poll_interval)
            except requests.exceptions.RequestException:
                return None
    else:
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            task = progress.add_task("⏳ Processing audio...", total=None)
            
            while True:
                try:
                    response = requests.get(url, headers=get_headers(), timeout=30)
                    
                    if response.status_code != 200:
                        console.print(f"[red]❌ Status check failed:[/red] {response.text}")
                        return None
                    
                    data = response.json()
                    status = data.get("status", "unknown")
                    
                    if status == "completed":
                        progress.update(task, description="[green]✅ Processing complete!")
                        return data
                    elif status == "failed":
                        error = data.get("error", "Unknown error")
                        console.print(f"\n[red]❌ Job failed:[/red] {error}")
                        return None
                    
                    time.sleep(poll_interval)
                
                except requests.exceptions.RequestException as e:
                    console.print(f"[red]❌ Connection error:[/red] {e}")
                    return None


def download_stems(job_data: dict, output_dir: Path, original_name: str, quiet: bool = False) -> list[Path]:
    """Download separated audio files."""
    output_dir.mkdir(parents=True, exist_ok=True)
    
    stems = job_data.get("outputAssets", [])
    
    if not stems:
        if not quiet:
            console.print("[yellow]⚠️ No output files found.[/yellow]")
        return []
    
    if not quiet:
        console.print(f"\n[blue]📥 Downloading {len(stems)} file(s)...[/blue]")
    
    saved_files = []
    base_name = Path(original_name).stem
    
    for stem in stems:
        stem_name = stem.get("name", "output")
        stem_url = stem.get("link") or stem.get("url")
        
        if not stem_url:
            continue
        
        extension = Path(stem_url).suffix.split("?")[0] or ".wav"
        output_file = output_dir / f"{base_name}_{stem_name}{extension}"
        
        try:
            response = requests.get(stem_url, stream=True, timeout=300)
            
            if response.status_code == 200:
                with open(output_file, "wb") as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)
                if not quiet:
                    console.print(f"   [green]✅[/green] {output_file.name}")
                saved_files.append(output_file)
            else:
                if not quiet:
                    console.print(f"   [red]❌[/red] Failed: {stem_name}")
        
        except requests.exceptions.RequestException as e:
            if not quiet:
                console.print(f"   [red]❌[/red] Download error: {e}")
    
    return saved_files


def separate_file(input_file: Path, output_dir: Path, quiet: bool = False) -> bool:
    """
    Separate a single file. Returns True on success.
    This is the core function used by both CLI and batch processing.
    """
    if not input_file.exists():
        if not quiet:
            console.print(f"[red]❌ File not found:[/red] {input_file}")
        return False
    
    if not is_valid_audio_file(input_file):
        if not quiet:
            console.print(f"[yellow]⚠️ Skipping unsupported file:[/yellow] {input_file.name}")
        return False
    
    asset_id = upload_file(input_file, quiet)
    if not asset_id:
        return False
    
    job_id = create_job(asset_id, quiet)
    if not job_id:
        return False
    
    job_data = wait_for_completion(job_id, quiet=quiet)
    if not job_data:
        return False
    
    saved = download_stems(job_data, output_dir, input_file.name, quiet)
    return len(saved) > 0


def separate(input_file: Path, output_dir: Path):
    """Main separation workflow for single file."""
    console.print("\n[bold cyan]🎧 Audioshake Voice Separator[/bold cyan]\n")
    
    if not check_api_key():
        sys.exit(1)
    
    success = separate_file(input_file, output_dir)
    
    if success:
        console.print(f"\n[bold green]🎉 Done![/bold green] Files saved to: {output_dir}\n")
    else:
        console.print("\n[red]❌ Separation failed.[/red]\n")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Extract vocals from audio using Audioshake API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s song.mp3
  %(prog)s song.wav -o ./vocals
  %(prog)s podcast.mp3 --output ~/Desktop/separated

For batch processing, use: python batch.py <directory>
        """,
    )
    
    parser.add_argument(
        "input",
        type=Path,
        help="Input audio file (MP3, WAV, FLAC, M4A, etc.)",
    )
    
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("./output"),
        help="Output directory (default: ./output)",
    )
    
    args = parser.parse_args()
    separate(args.input, args.output)


if __name__ == "__main__":
    main()