import argparse
from pathlib import Path
from parsers import juniper, arista

import sys
sys.path.append('../')
from nerds_utils import to_nerds, save_to_json  # noqa: E40


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--path', '-P', required=True, help='Path to jarchive directory')
    parser.add_argument('--out-dir', '-O', default='json', help='Path to output directory')
    parser.add_argument('--only-file', help='Only include devices specified in file')

    args = parser.parse_args()
    include_list = []
    if args.only_file:
        with open(args.only_file) as f:
            include_list = {line.strip() for line in f if line}

    for p in Path(args.path).glob('*.conf'):
        # need to read file "twice" 1 for detection of parser type.. and one for parsing
        with p.open() as f:
            if arista.is_ariasta(f):
                print("Skipping arista", p)
                continue

            # default to juniper
            data = juniper.parse(f)
            if not data or 'system' not in data:
                print('No juniper data', p)
                continue

            name = juniper.get_hostname(data)
            if not name:
                print('No host-name found for:', p)
                continue
            if include_list and name not in include_list:
                continue
            # some cleanup
            for key in ['login', 'root-authentication', 'services', 'syslog', 'archival']:
                if key in data['system']:
                    del data['system'][key]
            nerds = to_nerds(name, 'jarchive_juniper', data)
            save_to_json(nerds, args.out_dir, sort_keys=False)


if __name__ == '__main__':
    main()
