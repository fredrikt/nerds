from .base import ElementParser, get_hostname
from models import Router
from .interfaces import InterfaceParser
from .bgp import BgpPeeringParser


class RouterPaser:
    def parse(self, nodeTree, router_model=None, physical_interfaces=[]):
        self._clean(nodeTree)
        doc = ElementParser(nodeTree)
        router = Router()
        router.name = get_hostname(doc)
        router.version = doc.first("version").text()
        router.model = router_model
        router.interfaces = InterfaceParser().parse(nodeTree, physical_interfaces)
        router.bgp_peerings = BgpPeeringParser().parse(nodeTree)
        return router

    def _clean(self, nodeTree):
        # Remove unwanted stuff, e.g. logical-systems
        pass
