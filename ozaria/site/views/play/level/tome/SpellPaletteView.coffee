require('ozaria/site/styles/play/level/tome/spell-palette-view.sass')
CocoView = require 'views/core/CocoView'
{me} = require 'core/auth'
SpellPaletteEntryView = require './SpellPaletteEntryView'
SpellPaletteThangEntryView = require './SpellPaletteThangEntryView'
LevelComponent = require 'models/LevelComponent'
ThangType = require 'models/ThangType'
ace = require('lib/aceContainer')
aceUtils = require 'core/aceUtils'
store = require 'core/store'

module.exports = class SpellPaletteView extends CocoView
  id: 'spell-palette-view'
  template: require 'ozaria/site/templates/play/level/tome/spell-palette-view'
  controlsEnabled: true

  subscriptions:
    'level:disable-controls': 'onDisableControls'
    'level:enable-controls': 'onEnableControls'
    'surface:frame-changed': 'onFrameChanged'
    'tome:change-language': 'onTomeChangedLanguage'
    'tome:palette-clicked': 'onPaletteClick'
    'level:gather-chat-message-context': 'onGatherChatMessageContext'


  events:
    'click .sub-section-header': 'onSubSectionHeaderClick'
    'click .code-bank-close-btn': 'onCodeBankCloseBtnClick'
    'transitionend': 'onTransitionEnd'

  initialize: (options) ->
    {@level, @session, @thang, @useHero} = options
    @aceEditors = []
    @createPalette()
    $(window).on 'resize', @onResize

  getRenderData: ->
    c = super()
    c.entryGroups = @entryGroups
    c._ = _
    c

  afterRender: ->
    super()
    for group, entries of @entryGroups
      group = _.string.slugify(group)
      itemGroup = $('<div class="property-entry-item-group"></div>').appendTo @$el.find('.properties-'+group)
      entrySubGroups = _.groupBy entries, (entry) -> entry.doc.subSection || 'none'
      for subGroup, entries of entrySubGroups
        if subGroup != 'none'
          header = $("<div class='sub-section-header' data-panel='#sub-section-#{subGroup}-#{group}'>
              <span>#{subGroup}</span>
              <button tabindex='0' style='float:right;animation: none;position:absolute;right:10px;transform: rotate(90deg);' class='shepherd-next-button-active shepherd-button'></button>
            </a>").appendTo itemGroup
          itemSubGroup = $("<div class='property-entry-item-sub-group collapse' id='sub-section-#{subGroup}-#{group}'></div>").appendTo itemGroup
        for entry, entryIndex in entries
          if subGroup != 'none'
            itemSubGroup.append entry.el
          else
            itemGroup.append entry.el
          entry.render()  # Render after appending so that we can access parent container for popover
      @$el.addClass 'hero'
      @$el.toggleClass 'shortenize', Boolean true

  afterInsert: ->
    super()
    _.delay => @$el?.css('bottom', 0) unless $('#spell-view').is('.shown')

  updateCodeLanguage: (language) ->
    @options.language = language

  onResize: (e) =>
    @updateMaxHeight?()

  createPalette: ->
    Backbone.Mediator.publish 'tome:palette-cleared', {thangID: @thang.id}
    lcs = @supermodel.getModels LevelComponent

    allDocs = {}
    excludedDocs = {}
    for lc in lcs
      for doc in (lc.get('propertyDocumentation') ? [])
        if doc.codeLanguages and not (@options.language in doc.codeLanguages)
          excludedDocs['__' + doc.name] = doc
          continue
        if doc.type is 'snippet' then doc.owner = 'snippets'
        docCopy = Object.assign({ componentName: lc.get('name') }, doc)
        allDocs['__' + doc.name] ?= []
        allDocs['__' + doc.name].push docCopy

    methodsBankList = @options.level.get('methodsBankList') || []

    if methodsBankList.length == 0
      console.log("Methods Bank list is empty!!")
    else
      @organizePalette methodsBankList, allDocs, excludedDocs
    @publishAutoCompleteEvent(allDocs)

  # Reads the methods bank list and find its documentation from allDocs(i.e. docs coming from level components)
  # This also groups the list based on the section
  organizePalette: (methodsBankList, allDocs, excludedDocs) ->
    @entries = []
    @tts = @supermodel.getModels ThangType
    defaultSection = 'methods'
    defaultSubSection = if @options.level.isType('game-dev') then 'game' else 'hero'
    for prop, propIndex in methodsBankList
      section = prop.section
      subSection = prop.subSection
      unless section # Set default section and sub-section for methods bank
        section = defaultSection
        subSection = defaultSubSection
      propName = prop.name
      doc = _.find (allDocs['__' + propName] ? []), (doc) ->
        return true if !prop.componentName or (doc.componentName == prop.componentName)
      if not doc and not excludedDocs['__' + propName]
        console.log 'could not find doc for', propName, 'from', allDocs['__' + propName]
        doc = propName
      if doc
        @entries.push @addEntry(doc, section, subSection, false)
    @entryGroups = _.groupBy @entries, (entry) -> entry.doc.section


  addEntry: (doc, section, subSection, shortenize=true, isSnippet=false, item=null, showImage=false) ->
    if doc.type is 'spawnable'
      thangName = doc.name
      if @thang.spawnAliases[thangName]
        thangName = @thang.spawnAliases[thangName][0]
      info = @thang.buildables[thangName]
      tt = _.find @tts, (t) -> t.get('original') is info?.thangType
      if tt
        new SpellPaletteThangEntryView doc: doc, section: section, subSection: subSection, thang: tt, buildable: info, buildableName: doc.name, shortenize: shortenize, language: @options.language, level: @options.level, useHero: @useHero
    else
      writable = (if _.isString(doc) then doc else doc.name) in (@thang.apiUserProperties ? [])
      new SpellPaletteEntryView doc: doc, section: section, subSection: subSection, thang: @thang, shortenize: shortenize, isSnippet: isSnippet, language: @options.language, writable: writable, level: @options.level, item: item, showImage: showImage, useHero: @useHero

  # This uses the legacy logic to publish event for auto completion in the code editor using programmable properties.
  # This can potentially be merged with the logic in organizePalette, but currently doing that makes it behave differently, so keeping it as it is for now
  publishAutoCompleteEvent: (allDocs) ->
    propsByItem = {}
    itemsByProp = {}
    if @options.programmable
      propStorage =
        'this': 'programmableProperties'
        more: 'moreProgrammableProperties'
        Math: 'programmableMathProperties'
        Array: 'programmableArrayProperties'
        Object: 'programmableObjectProperties'
        String: 'programmableStringProperties'
        Global: 'programmableGlobalProperties'
        Function: 'programmableFunctionProperties'
        RegExp: 'programmableRegExpProperties'
        Date: 'programmableDateProperties'
        Number: 'programmableNumberProperties'
        JSON: 'programmableJSONProperties'
        LoDash: 'programmableLoDashProperties'
        Vector: 'programmableVectorProperties'
        HTML: 'programmableHTMLProperties'
        WebJavaScript: 'programmableWebJavaScriptProperties'
        jQuery: 'programmableJQueryProperties'
        CSS: 'programmableCSSProperties'
        snippets: 'programmableSnippets'
    else
      propStorage =
        'this': ['apiProperties', 'apiMethods']

    itemThangTypes = {}
    itemThangTypes[tt.get('name')] = tt for tt in @supermodel.getModels ThangType  # Also heroes

    # Make sure that we get the spellbook first, then the primary hand, then anything else.
    slots = _.sortBy _.keys(@thang.inventoryThangTypeNames ? {}), (slot) ->
      if slot is 'left-hand' then 0 else if slot is 'right-hand' then 1 else 2
    for slot in slots
      thangTypeName = @thang.inventoryThangTypeNames[slot]
      if item = itemThangTypes[thangTypeName]
        unless item.get('components')
          console.error 'Item', item, 'did not have any components when we went to assemble docs.'
        for component in item.get('components') ? [] when component.config
          for owner, storages of propStorage
            if props = component.config[storages]
              for prop in _.sortBy(props) when prop[0] isnt '_' and not itemsByProp[prop]  # no private properties
                continue if prop is 'moveXY' and @options.level.get('slug') is 'slalom'  # Hide for Slalom
                continue if @thang.excludedProperties and prop in @thang.excludedProperties
                propsByItem[item.get('name')] ?= []
                propsByItem[item.get('name')].push owner: owner, prop: prop, item: item
                itemsByProp[prop] = item
      else
        console.log @thang.id, "couldn't find item ThangType for", slot, thangTypeName

    for owner, storage of propStorage
      continue unless owner in ['this', 'more', 'snippets', 'HTML', 'CSS', 'WebJavaScript', 'jQuery']
      for prop in _.reject(@thang[storage] ? [], (prop) -> prop[0] is '_')  # no private properties
        continue if prop is 'say' and @options.level.get 'hidesSay'  # Hide for Dungeon Campaign
        continue if prop is 'moveXY' and @options.level.get('slug') is 'slalom'  # Hide for Slalom
        continue if @thang.excludedProperties and prop in @thang.excludedProperties
        propsByItem['Hero'] ?= []
        propsByItem['Hero'].push owner: owner, prop: prop, item: itemThangTypes[@thang.spriteName]
    Backbone.Mediator.publish 'tome:update-snippets', propGroups: propsByItem, allDocs: allDocs, language: @options.language

  onDisableControls: (e) -> @toggleControls e, false
  onEnableControls: (e) -> @toggleControls e, true
  toggleControls: (e, enabled) ->
    return if e.controls and not ('palette' in e.controls)
    return if enabled is @controlsEnabled
    @controlsEnabled = enabled
    @$el.find('*').attr('disabled', not enabled)
    @$el.toggleClass 'controls-disabled', not enabled

  onFrameChanged: (e) ->
    return unless e.selectedThang?.id is @thang?.id
    @options.thang = @thang = e.selectedThang  # Update our thang to the current version

  onTomeChangedLanguage: (e) ->
    @updateCodeLanguage e.language
    entry.destroy() for entry in @entries
    @createPalette()
    @render()

  onCodeBankCloseBtnClick: () ->
    $('.code-bank-left-arrow,.code-bank-right-arrow').toggleClass('hide')
    if $('#spell-palette-view').hasClass('open')
      $('#spell-palette-view').removeClass('open expand')
      $('#spell-palette-view .container').css('display','none')
    else
      $('#spell-palette-view').addClass('open expand')
      $('#spell-palette-view .container').css('display','block')
      if !$('.sub-section-header.selected').length
        $('.sub-section-header').first().click()
        $('.spell-palette-entry-view').first().click()

  onSubSectionHeaderClick: (e) ->
    $et = @$(e.currentTarget)
    target = @$($et.attr('data-panel'))
    isCollapsed = !target.hasClass('in')
    if isCollapsed
      target.collapse 'show'
      $et.find('.shepherd-button').removeClass('shepherd-next-button-active').addClass('shepherd-back-button-active')
      $et.toggleClass('selected', true)
    else
      target.collapse 'hide'
      $et.find('.shepherd-button').removeClass('shepherd-next-back-active').addClass('shepherd-next-button-active')
      $et.toggleClass('selected', false)

    setTimeout () =>
      @$('.nano').nanoScroller alwaysVisible: true
    , 200
    e.preventDefault()

  onPaletteClick: (e) ->
    @$el.addClass('expand')
    content = @$el.find(".rightContentTarget")
    content.html(e.entry.doc.initialHTML)
    content.i18n()
    @applyRTLIfNeeded()
    codeLanguage = e.entry.options.language
    oldEditor.destroy() for oldEditor in @aceEditors
    @aceEditors = []
    aceEditors = @aceEditors
    # Initialize Ace for each popover code snippet that still needs it
    content.find('.docs-ace').each ->
      aceEditor = aceUtils.initializeACE @, codeLanguage
      aceEditor.renderer.setShowGutter true
      aceEditors.push aceEditor

  onTransitionEnd: (e) ->
    store.dispatch('game/toggleCodeBank')

  onGatherChatMessageContext: (e) ->
    context = e.chat.context
    context.apiProperties = []
    for group, entries of @entryGroups
      for entry in entries
        if e.chat.example
          # Using entry.options.doc instead of entry.doc skips a lot of the data processing
          doc = _.omit(entry.options.doc, 'shortDescription', 'autoCompletePriority', 'snippets', 'userShouldCaptureReturn')
        else
          # Bakes in code language selection and translations
          doc = _.omit(entry.doc, 'ownerName', 'shortName', 'shorterName', 'title', 'initialHTML', 'shortDescription', 'autoCompletePriority', 'snippets', 'i18n', 'userShouldCaptureReturn')
          # TODO: remove more nested i18n
        doc.owner = 'hero' if doc.owner in ['this', 'more']
        delete doc.example unless doc.example
        delete doc.returns?.example if doc.returns and not doc.returns.example
        delete doc.returns?.description if doc.returns and not doc.returns.description
        #console.log doc
        context.apiProperties.push doc
    null

  destroy: ->
    entry.destroy() for entry in @entries
    @toggleBackground = null
    $(window).off 'resize', @onResize
    @setupManager?.destroy()
    super()
