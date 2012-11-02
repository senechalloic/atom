$ = require 'jquery'
_ = require 'underscore'
fs = require 'fs'

BindingSet = require 'binding-set'
Specificity = require 'specificity'

module.exports =
class Keymap
  bindingSets: null
  bindingSetsByFirstKeystroke: null
  queuedKeystrokes: null

  constructor: ->
    @bindingSets = []
    @bindingSetsByFirstKeystroke = {}

  bindDefaultKeys: ->
    @bindKeys "*",
      'meta-n': 'new-window'
      'meta-,': 'open-user-configuration'
      'meta-o': 'open'
      'meta-w': 'core:close'

    $(document).on 'new-window', => atom.newWindow()
    $(document).on 'open-user-configuration', => atom.open(atom.configFilePath)
    $(document).on 'open', => atom.open()

  bindKeys: (selector, bindings) ->
    bindingSet = new BindingSet(selector, bindings, @bindingSets.length)
    @bindingSets.unshift(bindingSet)
    for keystrokes of bindingSet.commandsByKeystrokes
      keystroke = keystrokes.split(' ')[0] # only index by first keystroke
      @bindingSetsByFirstKeystroke[keystroke] ?= []
      @bindingSetsByFirstKeystroke[keystroke].push(bindingSet)

  bindingsForElement: (element) ->
    keystrokeMap = {}
    currentNode = $(element)

    while currentNode.length
      bindingSets = @bindingSetsForNode(currentNode)
      _.defaults(keystrokeMap, set.commandsByKeystrokes) for set in bindingSets
      currentNode = currentNode.parent()

    keystrokeMap

  handleKeyEvent: (event) ->
    event.keystrokes = @multiKeystrokeStringForEvent(event)
    isMultiKeystroke = @queuedKeystrokes?
    @queuedKeystrokes = null

    firstKeystroke = event.keystrokes.split(' ')[0]
    bindingSetsForFirstKeystroke = @bindingSetsByFirstKeystroke[firstKeystroke]
    return true unless bindingSetsForFirstKeystroke?

    currentNode = $(event.target)
    while currentNode.length
      candidateBindingSets = @bindingSetsForNode(currentNode, bindingSetsForFirstKeystroke)
      for bindingSet in candidateBindingSets
        command = bindingSet.commandForEvent(event)
        if command
          continue if @triggerCommandEvent(event, command)
          return false
        else if command == false
          return false

        if bindingSet.matchesKeystrokePrefix(event)
          @queuedKeystrokes = event.keystrokes
          return false
      currentNode = currentNode.parent()

    !isMultiKeystroke

  bindingSetsForNode: (node, candidateBindingSets = @bindingSets) ->
    bindingSets = candidateBindingSets.filter (set) -> node.is(set.selector)
    bindingSets.sort (a, b) ->
      if b.specificity == a.specificity
        b.index - a.index
      else
        b.specificity - a.specificity

  triggerCommandEvent: (keyEvent, commandName) ->
    commandEvent = $.Event(commandName)
    commandEvent.keyEvent = keyEvent
    aborted = false
    commandEvent.abortKeyBinding = ->
      @stopImmediatePropagation()
      aborted = true
    $(keyEvent.target).trigger(commandEvent)
    aborted

  multiKeystrokeStringForEvent: (event) ->
    currentKeystroke = @keystrokeStringForEvent(event)
    if @queuedKeystrokes
      @queuedKeystrokes + ' ' + currentKeystroke
    else
      currentKeystroke

  keystrokeStringForEvent: (event) ->
    if event.originalEvent.keyIdentifier.indexOf('U+') == 0
      hexCharCode = event.originalEvent.keyIdentifier[2..]
      charCode = parseInt(hexCharCode, 16)
      key = @keyFromCharCode(charCode)
    else
      key = event.originalEvent.keyIdentifier.toLowerCase()

    modifiers = []
    if event.altKey and key isnt 'alt'
      modifiers.push 'alt'
    if event.ctrlKey and key isnt 'ctrl'
      modifiers.push 'ctrl'
    if event.metaKey and key isnt 'meta'
      modifiers.push 'meta'

    if event.shiftKey
      isNamedKey = key.length > 1
      modifiers.push 'shift' if isNamedKey
    else
      key = key.toLowerCase()

    [modifiers..., key].join('-')

  keyFromCharCode: (charCode) ->
    switch charCode
      when 8 then 'backspace'
      when 9 then 'tab'
      when 13 then 'enter'
      when 27 then 'escape'
      when 32 then 'space'
      when 127 then 'delete'
      else String.fromCharCode(charCode)
