import re
labels = dict(re.findall(r"^\s*(\w+)\s*=\s*\$([0-9a-fA-F]+)", open("build/labels.txt").read(), re.M))
end = int(labels["code_end"], 16)
print(f"code+tables end at ${end:04X} ({0x4000 - end} bytes free before VIC bank 1)")
