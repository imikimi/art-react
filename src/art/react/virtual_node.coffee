Foundation = require 'art-foundation'
ReactArtEngineEpoch = require './react_art_engine_epoch'
{
  log, compact, globalCount, flatten, BaseObject, shallowClone, inspect, objectKeyCount, isObject, deepEach, isPlainObject, keepIfRubyTrue,
  plainObjectsDeepEq
} = Foundation
{reactArtEngineEpoch} = ReactArtEngineEpoch

emptyObject = {}
module.exports = class VirtualNode extends BaseObject
  @propsEq: propsEq = plainObjectsDeepEq

  onNextReady: (f, forceEpoch = true) -> reactArtEngineEpoch.onNextReady f, forceEpoch, @

  @assignRefsTo: null

  constructor: (props = emptyObject) ->
    @_updateTarget = null # used for updating refs when rerendering
    @_parentComponent = null

    @key = props.key
    @props = props
    @_propsLength = -1

    # created once, then never changes
    @element = null

    VirtualNode._assignRefs @

  @getter
    propsLength: ->
      if @_propsLength >= 0
        @_propsLength
      else
        @_propsLength = objectKeyCount @props
  @setter
    propsLength: (v)-> @_propsLength = v

  ###
  Evaluate "f" in the thread the Element exists in.

  IN: (element) -> plainObjects
  OUT: promise returning function's plain-object-result

  # TODO: add worker support
  ###
  withElement: (f) ->
    new Promise (resolve) =>
      resolve f @element

  ###
  Lighter-weight than "withElement"

  IN:
    method: string
    args: 0 or more additional arguments
  OUT: promise returning function's plain-object-result

  Equivelent to:
    @withElement (element) -> element[method] args...

  ###
  sendToElement: (method, args...) ->
    new Promise (resolve) =>
      resolve @element[method] args...

  #####################
  # PRIVATE
  #####################
  @_separateConstructionParams: (args, propsOut, childrenOut) ->
    deepEach args, (obj) ->
      if isPlainObject obj
        propsOut[k] = v for k, v of obj
      else if keepIfRubyTrue obj
        childrenOut.push obj

  @_assignRefs: (node) ->
    if (key = node.key) && @assignRefsTo
      if @assignRefsTo[key] # TODO: This should probably be disabled unless in dev-mode
        console.warn """
          WARNING: Duplicate key found. This MUST be fixed for correct operation.
            key: #{inspect key}
            new VirtualNode: #{node.inspectedName}
            old VirtualNode: #{@assignRefsTo[key].inspectedName}
          """
      else
        @assignRefsTo[key] = node

  # TODO: only run in dev mode
  _validateChildren: (children) ->
    return children unless children
    for child in children
      unless child instanceof VirtualNode
        console.warn "invalid VirtualNode child": child, parent:@
        console.warn "Hint: Did you place properties AFTER a child element?" if isObject child
        throw new Error "VirtualNode child is not a VirtualNode.\ninvalid child: #{inspect child}\nparent: #{@inspectedName}"
    children

  _propsChanged: (virtualNode) ->
    newProps = virtualNode.props
    _propsLength = 0

    # return true if an existing prop changed
    for k, v of @props
      _propsLength++
      return true unless propsEq v, newProps[k]
    @_propsLength = _propsLength

    # props
    _propsLength != virtualNode.getPropsLength()

  # Post conditions:
  #   This and its entire Virtual-AIM sub-branch has been updated to be an exact clone of sourceNode,
  #   except it is _instantiated and the True-AIM is fully updated as well.
  # returns this
  _updateFrom: (sourceNode) ->
    sourceNode._updateTarget = @

  # return true if _updateFrom can work with sourceNode
  _canUpdateFrom: (sourceNode) -> false

  # Post conditions:
  #   @element is set
  #   Virtual-AIM sub-branch is fully generated
  #   All True-AIM elements have been created and assembled
  # returns this
  _instantiate: (parentComponent, bindToOrCreateNewParentElementProps) ->
    @_parentComponent = parentComponent
    @
