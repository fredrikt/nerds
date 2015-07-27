from .base import ElementParser
from models import Router
from .interfaces import InterfaceParser
from .bgp import BgpPeeringParser

class RouterPaser:
    def parse(self, nodeTree, router_model=None, physical_interfaces=[]):
        self._clean(nodeTree)
        doc = ElementParser(nodeTree)
        router = Router()
        router.name = self.get_hostname(doc)
        router.version = doc.first("version").text()
        router.model = router_model
        router.interfaces = InterfaceParser().parse(nodeTree, physical_interfaces)
        router.bgp_peerings = BgpPeeringParser().parse(nodeTree)
        return router

    def _clean(self,nodeTree):
        # Until we decide how we will handle logical-systems we remove them from
        # the configuration.
        logical_systems = nodeTree.getElementsByTagName('logical-systems')
        for item in logical_systems:
            item.parentNode.removeChild(item).unlink()


    def get_hostname(self, doc):
        hostname = doc.first("host-name").text()
        domain = doc.first('domain-name').text()
        if not hostname:
            raise ParserError('Could not find host-name in the Juniper configuration.')
        if domain:
            hostname += '.{0}'.format(domain)
        if 're0' in hostname or 're1' in hostname:
            hostname = hostname.replace('-re0','').replace('-re1','')
        return hostname
