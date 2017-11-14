class ParserError(Exception):
    pass


class ElementParser:
    """
        A Simple xml parsing helper. Wraps around xml.dom elements and allows chaining.
    """
    def __init__(self, nodeTree):
        self.nodeTree = nodeTree or EmptyTree()

    def text(self):
        """
            Returns the text of the current node.

            >>> elm = ElementParser(EmptyTree())
            >>> elm.text()
            ""
        """
        text = [child.data for child in self.nodeTree.childNodes if child.nodeType == child.TEXT_NODE]
        return "".join(text) or None

    def first(self, tag):
        """
            Gets the first matching tag. If no tag is present an EmptyTree will be returned.
            Wraps all elements in a new ElementParser.
        """
        res = self.all(tag)
        if len(res) > 0:
            return res[0]
        else:
            return ElementParser(EmptyTree())

    def all(self, tag):
        """
            Gets all tags matching supplied tag name.
            Wraps all elements in a new ElementParser.
        """
        return [ElementParser(n) for n in self.nodeTree.getElementsByTagName(tag)]

    def parent(self):
        """
            Returns parent node.
        """
        return ElementParser(self.nodeTree.parentNode)

    def tag(self):
        """
            Returns current tag name.
        """
        return self.nodeTree.tagName

    def attr(self, key, default=None):
        """
            Returns attribute with specified key or default
        """
        return self.nodeTree.getAttribute(key) or default


class EmptyTree:
    """
        A dummy class representing an empty xml node
    """
    def __init__(self):
        self.childNodes = []

    def getElementsByTagName(self, tag):
        return []


def get_hostname(doc):
    hostname = doc.first("host-name").text()
    domain = doc.first('domain-name').text()
    if not hostname:
        raise ParserError('Could not find host-name in the Juniper configuration.')
    if domain:
        hostname += '.{0}'.format(domain)
    if 're0' in hostname or 're1' in hostname:
        hostname = hostname.replace('-re0', '').replace('-re1', '')
    return hostname
