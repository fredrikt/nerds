from .base import ElementParser
from models import BgpPeering


class BgpPeeringParser:

    def parse(self, nodeTree):
        peerings = []
        bgpGroups = [g for bgp in ElementParser(nodeTree).all("bgp") if not bgp.attr('inactive') == 'inactive' for g in bgp.all("group")]

        for group in bgpGroups:
            if not group.attr('inactive') == 'inactive':
                gname = group.first("name").text()
                gtype = group.first("type").text()
                local_address = group.first("local-address").text()

                for neighbor in group.all("neighbor"):
                    if not neighbor.attr('inactive') == 'inactive':
                        peering = BgpPeering()
                        peering.type = gtype
                        peering.group = gname
                        peering.remote_address = neighbor.first("name").text()
                        peering.description = neighbor.first("description").text()
                        peering.local_address = local_address
                        peering.as_number = neighbor.first("peer-as").text()
                        peerings.append(peering)

        return peerings
