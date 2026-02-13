# Audioshake Voice Separator

A lightweight CLI tool to extract vocals from audio files using the Audioshake API.
Includes batch processing and a macOS drag-and-drop app.

## Features

- 🎵 Extract vocals from any audio file
- 📁 Batch process entire folders
- 🖱️ Drag-and-drop macOS app
- ⚡ Parallel processing for speed
- 🍎 Optimized for Apple Silicon

## Requirements

- Python 3.9+
- macOS (for drag-and-drop app) or any OS (for CLI)
- Audioshake API key

## Setup

### 1. Clone/download this project

### 2. Create virtual environment and install dependencies

```bash
cd audioshake-separator
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```plaintext

### 3. Configure your API key

```bash
cp .env.example .env
# Edit .env and add your Audioshake API key
```plaintext

### 4. (Optional) Create the drag-and-drop app

```bash
chmod +x create_app.sh
./create_app.sh
```plaintext

## Getting an API Key

1. Visit [audioshake.ai](https://www.audioshake.ai)
2. Sign up for an account
3. Navigate to your dashboard/API settings
4. Generate an API key
5. Copy it to your `.env` file

---

## Usage

### Single File (CLI)

```bash
python separator.py song.mp3
python separator.py song.wav -o ./vocals
```plaintext

### Batch Processing

```bash
# Process all audio in a folder
python batch.py ./music

# Recursive (include subfolders)
python batch.py ./music -r

# Custom output and parallel jobs
python batch.py ./music -o ./vocals -w 4
```plaintext

### Drag-and-Drop App

1. Run `./create_app.sh` to create the app
2. Drag audio files or folders onto `VocalSeparator.app`
3. Separated files appear in a `separated_vocals` folder

---

## CLI Options

### `separator.py`

| Option | Description |
|--------|-------------|
| `input` | Input audio file |
| `-o, --output` | Output directory (default: `./output`) |

### `batch.py`

| Option | Description |
|--------|-------------|
| `input` | Input directory or files |
| `-o, --output` | Output directory (default: `./output`) |
| `-r, --recursive` | Search subdirectories |
| `-w, --workers` | Parallel jobs (default: 2) |

---

## Supported Formats

- MP3
- WAV
- FLAC
- M4A
- OGG
- AAC
- WMA

---

## Output

For each input file, you'll get:
- `{filename}_vocals.wav` - Isolated vocal track
- `{filename}_instrumental.wav` - Background/instrumental track

---

## Troubleshooting

**"AUDIOSHAKE_API_KEY not found"**
- Make sure you've created a `.env` file with your API key
- Check that the key is correct

**"Upload failed"**
- Check your internet connection
- Verify your API key is valid
- Ensure the file isn't corrupted

**Drag-and-drop app doesn't work**
- Make sure you ran `create_app.sh` from the project directory
- Check that the virtual environment is set up
- Try running `python droplet.py <file>` directly to see errors