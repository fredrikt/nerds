from models import Interface
from .base import ElementParser, get_hostname
from util import logger

class InterfaceParser:
    def parse(self, nodeTree, physicalInterfaces=[]):
        host_name = get_hostname(ElementParser(nodeTree))
        interfaceNodes = [ 
                interface for i in ElementParser(nodeTree).all("interfaces") 
                if i.parent().tag() in ['configuration']
                for interface in i.all("interface") ]

        interfaces = []
        for node in interfaceNodes:
            interface = Interface()
            interface.name = node.first("name").text()
            if physicalInterfaces:
                if not interface.name in physicalInterfaces:
                    logger.warn("Interface {0} is configured but not found in {1}".format(interface.name, host_name))
                    continue
                else:
                    physicalInterfaces.remove(interface.name)

            interface.vlantagging = len(node.all("vlan-tagging")) > 0
            interface.bundle = node.first("bundle").text()
            interface.description = node.first("description").text()
            #TODO: tunnel dict..? Does it make sense when source/dest is empty?
            interface.tunneldict.append({
                'source': node.first("source").text(),
                'destination': node.first("destination").text(),
                })

            #Units
            interface.unitdict = [ self._unit(u) for u in node.all("unit") ]
            interfaces.append(interface)
        for iface in physicalInterfaces:
            interface = Interface()
            interface.name = iface
            interfaces.append(interface)

        return interfaces

    def _unit(self, unit):
        return {
                'unit': unit.first("name").text(),
                'description': unit.first("description").text(),
                'vlanid': unit.first("vlan-id").text(),
                'address': [ a.first("name").text() for a in unit.all("address") ],
                }
