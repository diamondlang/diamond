import sys
import os
import subprocess


# ==========================================
# DIAMOND CONFIGURATION
# ==========================================

config = {
    "Input": None,
    "Debug": False,
    "Robloxluau": False,
    "ExportToLuau": None
}


# ==========================================
# PATH DETECTION
# ==========================================

if getattr(sys, "frozen", False):
    # Running as a PyInstaller executable
    BASE_DIR = os.path.dirname(sys.executable)
else:
    # Running as a Python script
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))


LUTE_EXE = os.path.join(BASE_DIR, "lute.exe")
MAIN_LUAU = os.path.join(BASE_DIR, "main.luau")


# ==========================================
# ARGUMENT PARSING
# ==========================================

args = sys.argv[1:]

i = 0

while i < len(args):

    value = args[i]

    if value == "--debug":
        config["Debug"] = True

    elif value == "--robloxluau":
            config["Robloxluau"] = True

    elif value == "--exporttoluau":

        if i + 1 >= len(args):
            print("Error: --exporttoluau requires a filepath")
            sys.exit(1)

        config["ExportToLuau"] = args[i + 1]
        i += 1

    elif value.startswith("-"):
        print(f"Error: Unknown argument: {value}")
        sys.exit(1)

    elif config["Input"] is None:
        config["Input"] = value

    else:
        print(f"Error: Unknown argument: {value}")
        sys.exit(1)

    i += 1


# ==========================================
# VALIDATION
# ==========================================

if not os.path.isfile(LUTE_EXE):
    print(f"Error: Cannot find lute.exe")
    print(f"Expected location: {LUTE_EXE}")
    sys.exit(1)


if not os.path.isfile(MAIN_LUAU):
    print(f"Error: Cannot find main.luau")
    print(f"Expected location: {MAIN_LUAU}")
    sys.exit(1)

# ==========================================
# EXECUTION
# ==========================================

command = [
    LUTE_EXE,
    MAIN_LUAU,
    *args
]

try:

    result = subprocess.run(
        command,
        cwd=os.getcwd()
    )

    sys.exit(result.returncode)

except FileNotFoundError:
    print("Error: Failed to execute Lute.")
    print(f"Lute path: {LUTE_EXE}")
    sys.exit(1)

except KeyboardInterrupt:
    print("\nDiamond interrupted.")
    sys.exit(130)

except Exception as error:
    print(f"Error: {error}")
    sys.exit(1)
