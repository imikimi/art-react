Foundation = require 'art-foundation'
VirtualNode = require './virtual_node'
# {Element} = require './aim'
ReactArtEngineEpoch = require './react_art_engine_epoch'
{
  log, merge, mergeInto, clone, shallowClone
  inspect, compactFlatten, keepIfRubyTrue, BaseObject, fastBind
  slice
  isObject
  isString
  isArray
  isFunction
  globalCount
  time
  stackTime
  countStep
  createWithPostCreate
  arrayWithout
  upperCamelCase
  createObjectTreeFactory
  select
} = Foundation
{reactArtEngineEpoch} = ReactArtEngineEpoch

{HotLoader} = require 'art-foundation/dev_tools/webpack'
{runHot} = HotLoader


if ArtEngineCore = Neptune.Art.Engine.Core
  {StateEpoch, GlobalEpochCycle} = ArtEngineCore
  {stateEpoch} = StateEpoch
  {globalEpochCycle} = GlobalEpochCycle
  onNextStateEpochReady = (f) -> stateEpoch.onNextReady f
  timePerformance = (name, f) -> globalEpochCycle.timePerformance name, f
else
  onNextStateEpochReady = (f) -> reactArtEngineEpoch.onNextReady f
  timePerformance = (name, f) -> f()

# globalCount = ->
# time = stackTime = (f) -> f()

###
React.js vs ReactArtEngine
--------------------------

Generaly, ReactArtEngine is designed to work just like React.js. There is
some evolution, though, which I try to note below. -SBD

ReactArtEngine: "Instantiation"
-------------------------------

This is not a concept in React.js. It isn't important to the client, but it
is useful to understand in the implementation.

In-short: an non-instantiated component only has properties. It doesn't have
state and it isn't rendered. An instantiated component has state and gets
rendered at least once.

When a component is used in a render function, and with every re-render, it
an instance-object is created with standard javascript "new ComponentType."
However, that component instance is only a shell - it contains the
properties passed into the constructor and nothing else.

Once the entire render is done, the result is diffed against the current
Virtual-AIM. The component instance is compared against existing components
via the diff rules. If an existing, matching component exists, that
component is updated and the new instance is discard. However, if an
existing match doesn't exist, then the new component instance is
"instantiated" and added to the virtual-Aim.

QUESTIONS
---------

I just discovered it is possible, and useful, for a component to be rendered
after it is unmounted. I don't think this is consistent with Facebook-React.

Possible: if @setState is called after it is unmounted, it will trigger a
render. This can happen in FluxComponents when a subscription updates.

Useful: Why does this even make sense? Well, with Art.Engine we have
removedAnimations. That means the element still exists even though it has been
"removed." It exists until the animation completes. It is therefor useful to
continue to receive updates from React, where appropriate, during that "sunset"
time.

Thoughts: I think this is OK, though this changes what "unmounted" means. I just
fixed a bug where @state got altered without going through preprocessState first
when state changes after the component was unmounted. How should I TEST this???

###
module.exports = class Component extends VirtualNode
  @created: 0
  @topComponentInstances: []
  @rerenderAll: ->
    for component in @topComponentInstances
      component.rerenderAll()

  rerenderAll: ->
    @_queueRerender()
    for component in @subComponents
      component.rerenderAll()

  @createAndInstantiateTopComponent: (spec) ->
    Component.createComponentFactory(spec).instantiateAsTopComponent()

  unknownModule = {}
  @createComponentFactory: (spec, BaseClass = Component) ->
    componentClass = if spec?.prototype instanceof Component
      spec
    else if spec?.constructor == Object
      _module = getModule(spec) || unknownModule
      _module.uniqueComponentNameId ||= 1

      anonymousComponentName = "Anonymous#{BaseClass.getClassName()}"
      anonymousComponentName += "_#{_module.uniqueComponentNameId++}"
      anonymousComponentName += if _module.id then "_Module#{_module.id}" else '_ModuleUnknown'

      class AnonymousComponent extends BaseClass
        @_name: anonymousComponentName

        for k, v of spec
          @::[k] = v
    else
      throw new Error "Specification Object or class inheriting from Component required."

    createWithPostCreate componentClass

  @getModule: getModule = (spec = @::)->
    spec.module || spec.hotModule

  @getCanHotReload: -> @getModule()?.hot

  @hotReload: ->
    runHot @getModule(), (@_moduleState)=>
      if @_moduleState
        name = @getClassName()
        if (oldPrototype = @_moduleState.prototypesToUpdate?[name]) && oldPrototype != @prototype
          log "Component.hotReload - have oldPrototype to update"
          # add/update new properties
          for k, v of @prototype when @prototype.hasOwnProperty k
            oldPrototype[k] = v

          # delete removed properties
          for k, v of oldPrototype when !@prototype.hasOwnProperty(k) && oldPrototype.hasOwnProperty k
            delete oldPrototype[k]

          self.hotReload = @
          console.log "Component.hotReload #{@getClassName()}: updating instance bindings and hotReload them"
          # update all instances
          for instance in @_moduleState.hotInstances || []
            instance._bindFunctions()
            try instance.componentDidHotReload()
          console.log "Component.hotReload #{@getClassName()}: updating instance bindings done"

        (@_moduleState.prototypesToUpdate||={})[name] = oldPrototype || @prototype

  @allComponents: {}
  @postCreate: ->
    # log "Component defined: #{@getClassName()}" + if @getCanHotReload() then " (HOT)" else ""

    @hotReload()
    @toComponentFactory()

  nonBindingFunctions = "getInitialState
    componentWillReceiveProps
    componentWillMount
    componentWillUnmount
    componentWillUpdate
    componentDidMount
    componentDidUpdate
    render".split /\s+/

  @getBindList: ->
      if @hasOwnProperty "_bindList"
        @_bindList
      else
        @_bindList = @detectBindList()

  @detectBindList = ->
    prototype = @::
    k for k, v of prototype when k != "constructor" && isFunction(v) && prototype.hasOwnProperty(k) && k not in nonBindingFunctions

  @toComponentFactory: ->
    ret = createObjectTreeFactory (props, children) =>
      props.children = children if children.length > 0

      instance = new @ props
      instance._validateChildren props?.children # TODO: only in dev mode!

      instance
    , null, @getName() + "ComponentFactory"

    # OUT: new instance
    ret.instantiateAsTopComponent = (spec, options) ->
      ret(spec).instantiateAsTopComponent options

    ret

  @stateFields: (fields) ->
    @_stateFields = mergeInto @_stateFields, fields
    for field, initialValue of fields
      do (field) =>
        @_addSetter @::, field, (v) -> @setState field, v
        @_addGetter @::, field, -> @state[field]

  @createdComponents: null
  @pushCreatedComponent: (c)->
    @createdComponents ||= []
    @createdComponents.push c
  @resetCreatedComponents: -> @createdComponents = null

  emptyProps = {}
  constructor: (props = emptyProps) ->
    Component.created++
    globalCount "ReactComponent_Created"
    super props
    @state = {}
    @refs = null
    @_pendingState = null
    @_virtualAimBranch = null
    @_mounted = false
    @_wasMounted = false
    @_bindList = null
    @_applyingPendingState = false
    Component.pushCreatedComponent @

  ###
  SEE: VirtualElement#withElement for more
  IN: f = (concreteElement) -> x
  OUT: promise.then (x) ->
  ###
  withElement: (f) -> @_virtualAimBranch.withElement f

  #OUT: this
  instantiateAsTopComponent: (bindToOrCreateNewParentElementProps) ->
    Component.topComponentInstances.push @
    @_instantiate null, bindToOrCreateNewParentElementProps

  unbindTopComponent: ->
    unless 0 <= index = Component.topComponentInstances.indexOf @
      throw new Error "not a top component!"

    Component.topComponentInstances = arrayWithout Component.topComponentInstances, index
    @_unmount()

  @getter
    inspectedName: -> "#{@className}#{if @key then "-"+@key  else ''}"
    mounted: -> @_mounted

  onNextReady: (callback) ->
    reactArtEngineEpoch.onNextReady callback

  ################################################
  # Component API (based loosly on Facebook.React)
  ################################################

  # signatures:
  #   (newStateMapObject, callback) ->
  #     sets state from each k-v pair in newStateMapObject
  #     returns newStateMapObject
  #   (null, callback) ->
  #     no-op (except for callback)
  #     returns: null
  #   (stateKey, stateValue, callback) ->
  #     set one state
  #     returns: stateValue
  # callback is always called onNextReady
  setState: (newState, callback, callbackB) ->
    if isString newState
      return @_setSingleState newState, callback, callbackB

    @onNextReady callback

    if newState
      testState = @_pendingState || @state
      _state = null
      for k, v of newState when testState[k] != v
        _state ||= @_getStateToSet()
        _state[k] = v

    newState

  replaceState: (newState, callback) ->
    @_setPendingState newState
    @onNextReady callback

  forceUpdate: (callback) ->
    @_getPendingState()
    @onNextReady callback

  # Called when the component is instantiated.
  # ReactArtEngine ONLY: you CAN call setState/setSingleState during getInitialState:
  #   * setState calls populate @_pendingState and are merged after getInitialState: @state = merge @getInitialState(), @_pendingState
  #   * a reactArtEngineEpoch cycle is not queued; the only significant expense is one extra object creation to store the @_pendingState
  getInitialState: -> {}

  # TODO: Facebook React provides this. Add it if we have a concrete use for it.
  # @getDefaultProps: -> {}

  # returns a VirtalNode instance
  # render: -> Element()

  ################################################
  # Component LifeCycle based on Facebook React
  ################################################

  ###
  Called each time webpack hot-reloads a module.
  It is important that this change the components state to trigger a rerender.
  Make sure you add module: module to your component definition or
  run your definition in a runHot module, -> function
  ###
  componentDidHotReload: ->
    count = (@state._hotModuleReloadCount || 0) + 1
    @setState _hotModuleReloadCount: count

  # Invoked when a component is receiving new props. This method is not called
  # for the initial render.
  #
  # Use this as an opportunity to react to a prop transition before render()
  # is called by updating the state using this.setState(). The old props can
  # be accessed via this.props. Calling this.setState() within this function
  # will not trigger an additional render.
  componentWillReceiveProps: defaultComponentWillReceiveProps = (newProps) ->

  # Invoked once, both on the client and server, immediately before the initial
  # rendering occurs. If you call setState within this method, render() will see
  # the updated state and will be executed only once despite the state change.
  componentWillMount: defaultComponentWillMount = ->

  # Invoked immediately before a component is unmounted from the AIM.
  # Perform any necessary cleanup in this method, such as invalidating
  # timers or cleaning up any AIM elements that were created in componentDidMount.
  componentWillUnmount: defaultComponentWillUnmount = ->

  # Invoked immediately before rendering when new props or state are being
  # received. This method is not called for the initial render.
  #
  # Use this as an opportunity to perform preparation before an update occurs.
  #
  # Note: You cannot use @setState() in this method. If you need to update
  # state in response to a prop change, use componentWillReceiveProps instead.
  #
  # ReactArtEngine-specific: if newProps == @props then props didn't change; same with newState
  componentWillUpdate: defaultComponentWillUpdate = (newProps, newState)->

  # Invoked once immediately after the initial rendering occurs. At this
  # point in the lifecycle, the component has an AIM representation which you
  # can access via @getDOMNode() (TODO).
  componentDidMount: defaultComponentDidMount = ->

  # Invoked immediately after updating occurs. This method is not called for the initial render.
  # Use this as an opportunity to operate on the AIM when the component has been updated.
  #
  # ReactArtEngine-specific: if newProps == @props then props didn't change; same with newState
  componentDidUpdate: defaultComponentDidUpdate = (oldProps, oldState)->

  # TODO: Facebook React provides this. Add it if we have a concrete use for it.
  # NOTE: So far this seems unnecessary since we control the whole stack.
  # shouldComponentUpdate(newProps, newState) -> boolean

  ################################################
  # Component LifeCycle - ArtReact extensions
  ################################################

  ###
  Function:     preprocessProps

  When:         Called on component instantiation and any time props are updated

  IN:           newProps - The props received from the render call which created/updated this component

  OUT:          plain Object - becomes @props. Can be newProps, based on newProps or entirely new.

  Guarantee:    @props will allways be passed through preprocessProps before it is set.
                i.e. Your render code will never see a @props that hasen't been preprocessed.

  Be sure your preprocessProps: (requirements)
    - returns a plain Object
    - doesn't modify the newProps object passed in (create and return new object to add/alter props)
    - call super!

  Examples:
    # minimal
    preprocessProps: ->
      merge super, myProp: 123

    # a little of everything
    preprocessProps: ->
      newProps = super
      @setState foo: newProps.foo
      merge newProps, myProp: "dude: #{newProps.foo}"

  Okay:
    you can call @setState (Art.Flux.Component does exactly this!)

  Description:
    Either return exactly newProps which were passed in OR create a new, plain object.
    The returned object can contain anything you want.
    These are the props the component will see in any subsequent lifecycle calls.

  NOTE: Unique to Art.React. Not in Facebook's React.

  NOTES RE Facebook.React:
    Why add this? Well, often you want to apply a transformation to @props whenever its set OR it changes.
    With Facebook.React there is no one lifecycle place for this. Component instantiation/mounting
    and component updating are kept separate. I have found it is very error-prone to implement
    this common functionality manually on each component that needs it.

  ###
  preprocessProps: defaultPreprocessProps = (newProps) -> newProps

  ###
  Function:     preprocessState

  When:         preprocessState is called:
                  immediatly after getInitialState
                  after preprocessProps
                  after componentWillUpdate
                  before rendering

  IN:           newState - the state which is proposed to become @state
  OUT:          object which will become @state. Can be newState, be based on newState or completely new.

  Guarantees:   @state will allways be passed through preprocessState before it is set.
                i.e. Your render code will never see a @state that hasen't been preprocessed.

  NOTES RE Facebook.React:
    Why add this? Well, often you want to apply a transformation to @state whenever it is initialized
    OR it changes. With Facebook.React there is no one lifecycle place for this. Component
    instantiation/mounting and component updating are kept separate. I have found it is very
    error-prone to implement this common functionality manually on each component that needs it.

    An example of this is FluxComponents. They alter state implicitly as the subscription data comes in, and
    and component instantiation. preprocessState makes it easy to transform any data written via FluxComponents
    into a standard form.

  SBD NOTES TO SELF:
    I think:
      - it is OK to directly mutate newState, can we declare this offically part of the API?
      - calls to @setState in preprocessState will be applied NEXT epoch.
      - could make getInitialState obsolete, but I think we'll keep it around for convenience and consistency
  ###
  preprocessState: defaultPreprocessState = (newState) -> newState

  ######################
  # ART REACT EXTENSIONS
  ######################

  # findAll: t/f  # by default find won't return children of matching Elements, set to true to return all matches
  # verbose: t/f  # log useful information on found objects
  find: (pattern, {findAll, verbose} = {}, matches = [], path) ->

    pathString = if path then path + "/" + @inspectedName else @inspectedName

    matchFound = if usedFunction = isFunction pattern
      !!(functionResult = pattern @)
    else
      pathString.match pattern

    if matchFound
      if verbose
        @log if usedFunction
          matched: pathString, functionResult: functionResult
        else
          matched: pathString
      matches.push @
    else if verbose == "all"
      @log if usedFunction
        notMatched: pathString, functionResult: functionResult
      else
        notMatched: pathString

    if (!matchFound || findAll) && @subComponents
      child.find pattern, arguments[1], matches for child in @subComponents
    matches

  toCoffeescript: (indent)->
    @_virtualAimBranch.toCoffeescript indent

  getPendingState: -> @_pendingState || @state

  onNextReady: (f) ->
    if stateEpoch
      stateEpoch?.onNextReady f
    else
      super

  ######################
  # PRIVATE
  ######################
  _getStateToSet: ->
    if @_wasMounted then @_getPendingState() else @state

  _setSingleState: (stateKey, stateValue, callback) ->
    @onNextReady callback
    if @_pendingState || @state[stateKey] != stateValue
      @_getStateToSet()[stateKey] = stateValue

    stateValue

  _queueRerender: ->
    @_getPendingState()

  _setPendingState: (state) ->
    reactArtEngineEpoch.addChangingComponent @ unless @_pendingState || @_applyingPendingState
    @_pendingState = if state then shallowClone state else {}

  _getPendingState: ->
    @_pendingState || @_setPendingState @state

  _unmount: ->
    @_removeHotInstance()
    @_componentWillUnmount()

    @_virtualAimBranch?._unmount()
    @_mounted = false

  _addHotInstance: ->
    if moduleState = @class._moduleState
      (moduleState.hotInstances ||= []).push @

  _removeHotInstance: ->
    if moduleState = @class._moduleState
      {hotInstances} = moduleState
      if hotInstances && 0 <= index = hotInstances.indexOf @
        moduleState.hotInstances = arrayWithout hotInstances, index

  #OUT: this
  emptyState = {}
  _instantiate: (parentComponent, bindToOrCreateNewParentElementProps) ->
    super
    globalCount "ReactComponent_Instantiated"
    @_bindFunctions()

    @props = @_preprocessProps @props

    # globalCount "ReactComponent _instantiate", stackTime =>

    @_addHotInstance()
    @_componentWillMount()

    initialState = @getInitialState()
    __state = @state
    @state = emptyState

    @state = @_preprocessState merge @class._stateFields, __state, initialState

    @_virtualAimBranch = @_renderCaptureRefs()

    @_virtualAimBranch._instantiate @, bindToOrCreateNewParentElementProps
    @element = @_virtualAimBranch.element

    @_componentDidMount()
    @_wasMounted = @_mounted = true
    @

  emptyArray = []
  _renderCaptureRefs: ->
    ret = null
    timePerformance "reactRender", =>
      globalCount "ReactComponent_Rendered"
      VirtualNode.assignRefsTo = @refs = {}
      Component.resetCreatedComponents()

      # log "render component: #{@className}"

      ret = @render()
      throw new Error "#{@className}: render must return a VirtualNode. Got: #{inspect ret}" unless ret instanceof VirtualNode

      @subComponents = Component.createdComponents || emptyArray
      VirtualNode.assignRefsTo = null

    ret

  _updateRefsAfterReRender: ->
    for k, v of @refs
      if _updateTarget = @refs[k]._updateTarget
        @refs[k] = _updateTarget

    for c, i in @subComponents when update = c._updateTarget
      @subComponents[i] = update

  _canUpdateFrom: (b)->
    @class == b.class &&
    @key == b.key

  _shouldReRenderComponent: (componentInstance) ->
    @_propsChanged(componentInstance) || @_pendingState

  # renders the component and updates the Virtual-AIM as needed.
  _reRenderComponent: ->

    newRenderResult = @_renderCaptureRefs()

    if @_virtualAimBranch._canUpdateFrom newRenderResult
      @_virtualAimBranch._updateFrom newRenderResult
      @_updateRefsAfterReRender()
    else
      # TODO - this should probably NOT be an error, but it isn't easy to solve.
      # Further, this is wrapped up with the pending feature of optionally returing an array of Elements from the render function.
      # Last, this should not be special-cased if possible. VitualElement children handling code should be used to handle these updates.

      console.error """
        REACT-ART-ENGINE ERROR - The render function's top-level Component/VirtualElement changed 'too much.' The VirtualNode returned by a component's render function cannot change its Type or Key.

        Solution: Wrap your changing VirtualNode with a non-changing VirtualElement.

        Offending component: #{@classPathName}
        Offending component assigned to: self.offendingComponent
        """
      console.log "CHANGED-TOO-MUCH-ERROR-DETAILS - all these properties must be the same on the oldRoot and newRoot",
        oldRoot: select @_virtualAimBranch, "key", "elementClassName", "class"
        newRoot: select newRenderResult, "key", "elementClassName", "class"
      self.offendingComponent = @
      @_virtualAimBranch?._unmount()
      (@_virtualAimBranch = newRenderResult)._instantiate @

    @element = @_virtualAimBranch.element

  # 1. Modifies @ to be an exact clone of componentInstance.
  # 2. Updates the true-AIM as we go.
  # 3. returns @
  _updateFrom: (componentInstance) ->

    super
    if @_shouldReRenderComponent componentInstance
      globalCount "ReactComponent_UpdateFromTemporaryComponent_Changed"
      @_applyPendingState componentInstance.props
    else
      globalCount "ReactComponent_UpdateFromTemporaryComponent_NoChange"

    @

  # NOTE: newProps got preprocessed when the Component instance this one is updating from was constructed.
  _applyPendingState: (newProps) ->
    return unless @_pendingState || newProps
    @_applyingPendingState = true

    if newProps
      newProps = @_preprocessProps newProps
      @_componentWillReceiveProps newProps

    oldProps = @props
    oldState = @state
    newProps ||= oldProps
    newState = @_pendingState || oldState

    @_componentWillUpdate newProps, newState

    ###
    React.js forbids calling setState from componentWillUpdate, but I see no reason for this.
    This next line safely supports state updates in componentWillUpdate in a pure-functionalish way:
      after a setState in @componentWillUpdate,
      the new state will not be visible in the remainder of that @componetWillUpdate call
      but it will be visible in any subsquent lifecycle call such as @render
    ###
    newState = @_pendingState || oldState
    @_pendingState = null

    @props = newProps
    @state = @_preprocessState newState

    @_applyingPendingState = false
    @_reRenderComponent()

    @_componentDidUpdate oldProps, oldState

  _bindFunctions: ->
    oldBindList = @_bindList
    newBindList = @class.getBindList()

    # console.error "no bindlist for class", @class unless newBindList
    # log "@class.newBindList", newBindList, oldBindList

    if oldBindList
      delete @[k] for k in oldBindList when k not in newBindList

    for k in newBindList
      @[k] = fastBind @class.prototype[k], @

    # log bound: (k for k in Object.keys @ when isFunction @[k])
    @_bindList = newBindList


  ########################
  # PRIVATE
  # LifeCycle Management
  ########################

  # NOTE: The reason for defaultComponent* values instead of making the defaults NULL
  #   is so inheritors can call "super" safely.
  # IDEA: We could make createComponentFactory gather up all custom life-cycle functions,
  #   and execute each in sequence therefor they don't need to call super.
  #   We could also enable mixins this way.
  _componentWillReceiveProps: (newProps) ->
    return if defaultComponentWillReceiveProps == @componentWillReceiveProps
    timePerformance "reactLC", =>
      @componentWillReceiveProps newProps

  _preprocessProps: (props) ->
    return props if defaultPreprocessProps == @preprocessProps
    timePerformance "reactLC", =>
      props = @preprocessProps props
    props

  _preprocessState: (state) ->
    return state if defaultPreprocessState == @preprocessState
    timePerformance "reactLC", =>
      state = @preprocessState state
    state

  _componentWillMount: ->
    return if defaultComponentWillMount == @componentWillMount
    timePerformance "reactLC", =>
      @componentWillMount()

  _componentWillUnmount: ->
    return if  defaultComponentWillUnmount == @componentWillUnmount
    timePerformance "reactLC", =>
      @componentWillUnmount()

  _componentWillUpdate: (newProps, newState)->
    return unless defaultComponentWillUpdate
    timePerformance "reactLC", =>
      @componentWillUpdate newProps, newState

  _componentDidMount: ->
    return if defaultComponentDidMount == @componentDidMount
    @onNextReady =>
      timePerformance "reactLC", =>
        @componentDidMount()

  _componentDidUpdate: (oldProps, oldState)->
    return if defaultComponentDidUpdate == @componentDidUpdate
    @onNextReady =>
      timePerformance "reactLC", =>
        @componentDidUpdate oldProps, oldState
