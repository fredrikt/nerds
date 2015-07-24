class ElementParser:
    """
        A Simple xml parsing helper. Wraps around xml.dom elements and allows chaining.
    """
    def __init__(self, nodeTree):
        self.nodeTree = nodeTree
    def text(self):
        """
            Returns the text of the current node.
            
            >>> elm = ElementParser(EmptyTree())
            >>> elm.text()
            ""
        """
        text = [ child.data for child in self.nodeTree.childNodes if child.nodeType == child.TEXT_NODE ]
        return "".join(text) or None
    def first(self,tag):
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

class EmptyTree:
    """
        A dummy class representing an empty xml node
    """
    def __init__(self):
        self.childNodes = []
    def getElementsByTagName(self, tag):
        return []
