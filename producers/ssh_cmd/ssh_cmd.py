from fabric.api import run, settings, env, quiet, hosts

# Would be nice to use hosts list instead of host_string...
def ssh_cmd(host, cmd, options={}):
    with settings(quiet(), use_ssh_config = True, host_string = host):
        output = run(cmd)
    return output

if __name__ == '__main__':
    print ssh_cmd("persephone", "ls -l").splitlines()
        
