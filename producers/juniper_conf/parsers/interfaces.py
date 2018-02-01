from models import Interface
from .base import ElementParser, get_hostname
from util import logger


class InterfaceParser:
    def parse(self, nodeTree, physicalInterfaces=[]):
        host_name = get_hostname(ElementParser(nodeTree))
        interfaceNodes = [
            interface for i in ElementParser(nodeTree).all("interfaces")
            if i.parent().tag() in ['configuration']
            for interface in i.all("interface")
        ]

        interface_map = {}
        for node in interfaceNodes:
            iname = node.first("name").text()
            interface = interface_map.get(iname, self.new_interface(iname))

            if physicalInterfaces and iname not in physicalInterfaces:
                logger.warn("Interface {0} is configured but not found in {1}".format(iname, host_name))
                continue

            # Update interface
            self._interface(interface, node)
            interface_map[interface.name] = interface

        # Add remaining physical interfaces if any
        for iface in physicalInterfaces:
            if iface not in interface_map:
                interface_map[iface] = self.new_interface(iface)

        # Handle logical systems
        logicalNodes = [
            iface for i in ElementParser(nodeTree).all("interfaces")
            if i.parent().tag() in ['logical-systems']
            for iface in i.all("interface")
        ]
        for node in logicalNodes:
            iname = node.first("name").text()
            interface = interface_map.get(iname, self.new_interface(iname))
            # Only update unitdict for logical systems
            interface.unitdict += [self._unit(u) for u in node.all("unit")]
            interface_map[interface.name] = interface

        return sorted(interface_map.values(), key=lambda i: i.name)

    def new_interface(self, name):
        interface = Interface()
        interface.name = name
        return interface

    def _interface(self, interface, node):
        interface.vlantagging = len(node.all("vlan-tagging")) > 0
        interface.bundle = node.first("bundle").text()
        interface.description = node.first("description").text()
        interface.inactive = node.attr('inactive') == 'inactive'
        interface.tunneldict.append({
            'source': node.first("source").text(),
            'destination': node.first("destination").text(),
        })
        interface.unitdict += [self._unit(u) for u in node.all("unit")]

    def _unit(self, unit):
        return {
            'unit': unit.first("name").text(),
            'description': unit.first("description").text(),
            'vlanid': unit.first("vlan-id").text(),
            'address': [a.first("name").text() for a in unit.all("address")],
            'inactive': unit.attr('inactive') == 'inactive',
        }
