#!/usr/bin/env python3
"""
Generate profile.json for a Proton .wcp package.
Usage: generate_profile.py <output_path> <version_name> <version_code> <description> [profile_type] [prefix_pack_name]
"""
import json
import sys


def main():
    if len(sys.argv) < 5:
        print(
            "Usage: generate_profile.py <output_path> <version_name> <version_code> "
            "<description> [profile_type] [prefix_pack_name]"
        )
        sys.exit(1)

    out_path = sys.argv[1]
    version_name = sys.argv[2]
    version_code = int(sys.argv[3])
    description = sys.argv[4]
    profile_type = sys.argv[5] if len(sys.argv) > 5 else "proton"
    prefix_pack_name = sys.argv[6] if len(sys.argv) > 6 else "prefixPack.txz"
    profile_type_lower = profile_type.lower()
    if profile_type_lower == "wine":
        profile_type = "Wine"
    elif profile_type_lower == "proton":
        profile_type = "Proton"

    # GameNative uses "wine" as the paths key for BOTH Proton and Wine type profiles.
    # Confirmed from GameNative/proton-wine build-proton.yml CI workflow.
    paths_key = "wine"
    profile = {
        "type": profile_type,
        "versionName": version_name,
        "versionCode": version_code,
        "description": description,
        "files": [],
        paths_key: {
            "binPath": "bin",
            "libPath": "lib",
            "prefixPack": prefix_pack_name
        }
    }

    with open(out_path, "w") as f:
        json.dump(profile, f, indent=2)

    print(f"profile.json written to {out_path}")


if __name__ == "__main__":
    main()
