Foundation = require 'art-foundation'
React = require '../Core'
{log, mergeInto} = Foundation
{createObjectTreeFactories} = require 'art-object-tree-factory'
{VirtualElement, objectTreeFactoryOptions} = React
{getNextPageIndexes} = require "./PagingScrollElement"

# Note, this needs to work in the main AND worker threads...
# That's why this doesn't use ArtEngine.ElementFactory.elementClasses.
standardArtEngineElementClassNames = "
  BitmapElement
  BlurElement
  CanvasElement
  ShapeElement
  Element
  FillElement
  OutlineElement
  PagingScrollElement
  RectangleElement
  ShadowElement
  TextElement
  TextInputElement
  ScrollElement
  "

{postProcessProps} = objectTreeFactoryOptions

module.exports = class Aim
  @createVirtualElementFactories: (VirtualElementClass, elementClassNames = standardArtEngineElementClassNames) ->
    mergeInto @, createObjectTreeFactories objectTreeFactoryOptions, elementClassNames, (elementClassName) ->
      (props, children) ->
        new VirtualElementClass elementClassName,
          postProcessProps props
          children

    @bindHelperFunctions()
    @

  @bindHelperFunctions: ->
    @PagingScrollElement.getNextPageIndexes = getNextPageIndexes
