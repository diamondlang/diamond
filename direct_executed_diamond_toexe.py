
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BASE_DIR = (
    Path(sys.executable).resolve().parent
    if getattr(sys, "frozen", False)
    else Path(__file__).resolve().parent
)

LUTE_EXE = BASE_DIR / "lute.exe"
MAIN_LUAU = BASE_DIR / "main.luau"
EDIT_BIN = BASE_DIR / "editbin.exe"

parser = argparse.ArgumentParser(
    prog="diamondtoexe",
    description="Build a Diamond .dd file into a standalone executable."
)

parser.add_argument("input", help="Input .dd file")
parser.add_argument(
    "--deleteconsole",
    action="store_true",
    help="Build without a console window"
)

args = parser.parse_args()

# Resolve input
input_file = Path(args.input).resolve()

if not input_file.is_file():
    parser.error(f"Input file does not exist: {input_file}")

# Check required files
for file in (LUTE_EXE, MAIN_LUAU):
    if not file.is_file():
        parser.error(f"Required file not found: {file}")

if args.deleteconsole and not EDIT_BIN.is_file():
    parser.error(f"editbin.exe not found: {EDIT_BIN}")

# Output filename
output_file = Path.cwd() / (input_file.stem + ".exe")

try:
    with tempfile.TemporaryDirectory(prefix="diamondtoexe_") as temp:
        temp_dir = Path(temp)

        luau_file = temp_dir / "compiled.luau"
        exe_file = temp_dir / "compiled.exe"

        print("Compiling Diamond to Luau...")

        subprocess.run(
            [
                str(LUTE_EXE),
                str(MAIN_LUAU),
                str(input_file),
                "--exporttoluau",
                str(luau_file)
            ],
            cwd=os.getcwd(),
            check=True
        )

        print("Compiling Luau to Exe...")

        subprocess.run(
            [
                str(LUTE_EXE),
                "compile",
                str(luau_file),
                "--output",
                str(exe_file)
            ],
            cwd=os.getcwd(),
            check=True
        )

        if args.deleteconsole:
            print("Editing Exe to remove console...")

            subprocess.run(
                [
                    str(EDIT_BIN),
                    "/SUBSYSTEM:WINDOWS",
                    str(exe_file)
                ],
                cwd=os.getcwd(),
                check=True
            )

        # Copy executable to current directory
        shutil.copy2(exe_file, output_file)

    print(f"File exported: {output_file}")

except subprocess.CalledProcessError as error:
    print(f"Compilation failed! Exit code: {error.returncode}")
    sys.exit(error.returncode)
except OSError as error:
    print(f"Error: {error}")
    sys.exit(1)
