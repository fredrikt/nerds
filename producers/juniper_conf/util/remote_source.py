try:
    from util import logger
    import pexpect
    from xml.dom import minidom
    from xml.parsers.expat import ExpatError
    importError = False
except ImportError:
    logger.error("Install pexpect to be able to fetch config from remote source")
    importError = True


class RemoteSource:
    def __init__(self, host, username, password):
        self.host = host
        self.username = username
        self.password = password

    def send_command(self, command):
        if importError:
            return None
        ssh_newkey = 'Are you sure you want to continue connecting'
        login_choices = [ssh_newkey, 'Password:', 'password:', pexpect.EOF, "--- JUNOS", "Ubuntu"]

        try:
            ssh_cmd = 'ssh -o ConnectTimeout=10 {user}@{host}'.format(user=self.username, host=self.host)
            ssh = pexpect.spawn(ssh_cmd)
            i = ssh.expect(login_choices, timeout=12)
            if i == 0:
                ssh.sendline('yes')
                # Try again :)
                i = ssh.expect(login_choices)
            if i == 1 or i == 2:
                ssh.sendline(self.password)
            elif i == 3:
                logger.error("[%s] I either got key problems or connection timeout." % self.host)
                return None
            ssh.expect('>', timeout=60)
            # Ready to send cmd
            ssh.sendline(command)
            ssh.expect('</rpc-reply>', timeout=600)   # expect end of the XML

            xml = ssh.before  # take everything printed before last expect()
            ssh.sendline('exit')
        except pexpect.ExceptionPexpect as e:
            msg = 'No message'
            if e.message:
                msg = e.message.splitlines()[0]
            logger.error('[{}] unable to send command - error: {}'.format(self.host, msg))
            return None

        xml += '</rpc-reply>'  # Add the end element as pexpect steals it
        # Remove the first line in the output which is the command sent
        # to JunOS.

        # Remove everything before command
        xml = self._strip_before(xml, command)
        try:
            xmldoc = minidom.parseString(xml)
        except ExpatError:
            logger.error('Malformed XML input from %s.' % self.host)
            print(xml)
            return None
        return xmldoc

    def _strip_before(self, target, what):
        out = ""
        match = False
        for line in target.splitlines(True):
            if what in line:
                match = True
            elif match:
                out += line
        return out


class JunosRemoteSource(RemoteSource):
    def show_configuration(self):
        return self.send_command("show configuration | display xml | no-more")

    def show_interfaces(self):
        return self.send_command("show interfaces | display xml | no-more")

    def show_hardware(self):
        return self.send_command("show chassis hardware | display xml | no-more")
