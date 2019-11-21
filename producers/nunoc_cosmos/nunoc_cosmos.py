import argparse
import os
import yaml
import re
import subprocess
import sys
sys.path.append('../')
from utils.nerds import to_nerds
from utils.file import save_to_json
# Input nunco_repo_path
#   Globs dirs in root


# glob folders for check against regexes
# load yaml file ./global/overlay/etc/puppet/cosmos-rules.yaml
# loop over entries
#   if entry has sunet_iaas_cloud
#       lookup IPs
clean_name_re = re.compile('^.*@')
ipv4_re = re.compile('(\d{1,3}(\.\d{1,3}){3})')
ipv6_re = re.compile('(:?[0-9a-fA-F]+(:[0-9a-fA-F]*)+)')


def regex_check(pattern, candidates):
    return [candidate for candidate in candidates if re.search(pattern, candidate)]


def clean_name(name):
    return clean_name_re.sub('', name)


def main(nunoc_path, out_path):
    potential_hosts = set([path for path in os.listdir(nunoc_path) if os.path.isdir(os.path.join(nunoc_path, path))])
    hosts = set([])
    with open(os.path.join(nunoc_path, 'global/overlay/etc/puppet/cosmos-rules.yaml')) as yaml_file:
        for k, v in yaml.safe_load(yaml_file).items():
            if 'sunet_iaas_cloud' in v:
                hosts.update([clean_name(host) for host in regex_check(k, potential_hosts)])
    # for each host lookup ip
    for host in hosts:
        try:
            out = subprocess.check_output(['host', host])
        except subprocess.CalledProcessError:
            out = ''

        ipv4_match = ipv4_re.search(out)
        ipv6_match = ipv6_re.search(out)
        addresses = []
        if ipv4_match:
            addresses.append(ipv4_match.group(1))
        if ipv6_match:
            addresses.append(ipv6_match.group(1))

        nerds = to_nerds(
            host,
            'nunoc_cosmos',
            {
                'addresses': addresses,
                'sunet_iaas': True,
                'managed_by': 'Puppet',
            })
        save_to_json(nerds, out_path)


def cli():
    parser = argparse.ArgumentParser(description='NUNOC-ops iaas producer')
    parser.add_argument('--path', '-P', required=True, help='the path to a nunoc-ops repository')
    parser.add_argument('--out', '-O', default='json')
    return parser.parse_args()


if __name__ == '__main__':
    args = cli()
    main(args.path, args.out)
