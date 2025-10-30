import os, json, pathlib

def build_tree(base):
    tree = {}
    for root, dirs, files in os.walk(base):
        rel_root = pathlib.Path(root).relative_to(base)
        tree[str(rel_root)] = {
            "dirs": sorted(dirs),
            "files": sorted(files)
        }
    return tree

if __name__ == "__main__":
    base = pathlib.Path(__file__).resolve().parents[1] / "lib"
    result = build_tree(base)
    print(json.dumps(result, indent=2))
