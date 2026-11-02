#!/usr/bin/env python3
"""Remove identifying PNG/JPEG metadata without decoding or changing image pixels.
Usage: python3 scripts/strip_image_metadata.py input.png output.png
Keep originals outside the public repository. EXIF orientation must already be normal.
"""
from pathlib import Path
import argparse

def strip(data):
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        output=bytearray(data[:8]);offset=8
        while offset+12<=len(data):
            size=int.from_bytes(data[offset:offset+4],'big');end=offset+12+size
            if end>len(data):raise ValueError('Truncated PNG')
            kind=data[offset+4:offset+8]
            if kind not in {b'tEXt',b'zTXt',b'iTXt',b'eXIf',b'tIME'}:output.extend(data[offset:end])
            offset=end
            if kind==b'IEND':return bytes(output)
        raise ValueError('Missing PNG end')
    if data.startswith(b'\xff\xd8'):
        output=bytearray(data[:2]);offset=2
        while offset+4<=len(data):
            if data[offset]!=255:raise ValueError('Invalid JPEG marker')
            marker=data[offset+1]
            if marker==0xDA: # Entropy-coded pixel stream and remaining scans stay verbatim.
                output.extend(data[offset:]);return bytes(output)
            size=int.from_bytes(data[offset+2:offset+4],'big');end=offset+2+size
            if size<2 or end>len(data):raise ValueError('Truncated JPEG')
            if marker!=0xFE and (not 0xE0<=marker<=0xEF or marker in {0xE0,0xE2,0xEE}):output.extend(data[offset:end])
            offset=end
        raise ValueError('Missing JPEG pixel stream')
    raise ValueError('Only PNG and JPEG are supported')

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('input',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();data=args.input.read_bytes();clean=strip(data)
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_bytes(clean)
    print(f'{args.output.name}: removed {len(data)-len(clean)} metadata bytes; pixel stream preserved')
if __name__=='__main__':main()
