require('app/styles/modal/auth-modal.sass')
ModalView = require 'views/core/ModalView'
template = require 'app/templates/core/auth-modal'
forms = require 'core/forms'
User = require 'models/User'
errors = require 'core/errors'
RecoverModal = require 'views/core/RecoverModal'
storage = require 'core/storage'
globalVar = require 'core/globalVar'

module.exports = class AuthModal extends ModalView
  id: 'auth-modal'
  template: template
  trapsFocus: false  # TODO: re-enable this in a way that doesn't break Google login Noty

  events:
    'click #switch-to-signup-btn': 'onSignupInstead'
    'submit form': 'onSubmitForm'
    'keyup #name': 'onNameChange'
    'click #google-login-button': 'onClickGPlusLoginButton'
    'click #facebook-login-btn': 'onClickFacebookLoginButton'
    'click #clever-signup-btn': 'onClickCleverSignupButton'
    'click #close-modal': 'hide'
    'click [data-toggle="coco-modal"][data-target="core/RecoverModal"]': 'openRecoverModal'

  # Initialization

  initialize: (options={}) ->
    @previousFormInputs = options.initialValues or {}
    @previousFormInputs.emailOrUsername ?= @previousFormInputs.email or @previousFormInputs.username

    if me.useSocialSignOn()
      # TODO: Switch to promises and state, rather than using defer to hackily enable buttons after render
      application.gplusHandler.loadAPI({ success: => _.defer =>
        @$('#google-login-button').attr('disabled', false)
        @onClickGPlusLoginButton()
      })
      application.facebookHandler.loadAPI({ success: => _.defer => @$('#facebook-login-btn').attr('disabled', false) })
    @subModalContinue = options.subModalContinue

  afterRender: ->
    super()
    @playSound 'game-menu-open'

  afterInsert: ->
    super()
    _.delay (=> $('input:visible:first', @$el).focus()), 500

  onSignupInstead: (e) ->
    CreateAccountModal = require('./CreateAccountModal')
    modal = new CreateAccountModal({initialValues: forms.formToObject @$el, @subModalContinue})
    globalVar.currentView.openModalView(modal)

  onSubmitForm: (e) ->
    @playSound 'menu-button-click'
    e.preventDefault()
    forms.clearFormAlerts(@$el)
    @$('#unknown-error-alert').addClass('hide')
    userObject = forms.formToObject @$el
    res = tv4.validateMultiple userObject, formSchema
    return forms.applyErrorsToForm(@$el, res.errors) unless res.valid
    showingError = false
    new Promise(me.loginPasswordUser(userObject.emailOrUsername, userObject.password).then)
    .catch((jqxhr) =>
      if jqxhr.status is 401
        errorID = jqxhr.responseJSON.errorID
        if errorID is 'not-found'
          forms.setErrorToProperty(@$el, 'emailOrUsername', $.i18n.t('loading_error.user_not_found'))
          showingError = true
        if errorID is 'wrong-password'
          forms.setErrorToProperty(@$el, 'password', $.i18n.t('account_settings.wrong_password'))
          showingError = true
      else if jqxhr.status is 429
        showingError = true
        forms.setErrorToProperty(@$el, 'emailOrUsername', $.i18n.t('loading_error.too_many_login_failures'))

      if not showingError
        @$('#unknown-error-alert').removeClass('hide')
    )
    .then(=>
      application.tracker.identifyAfterNextPageLoad()
      return application.tracker.identify()
    )
    .finally(=>
      unless showingError
        if window.nextURL
          window.location.href = window.nextURL
        else
          loginNavigate(@subModalContinue)
    )


  # Google Plus

  onClickGPlusLoginButton: ->
    btn = @$('#google-login-button')
    application.gplusHandler.connect({
      context: @
      success: (resp = {}) ->
        btn.find('.sign-in-blurb').text($.i18n.t('login.logging_in'))
        btn.attr('disabled', true)
        application.gplusHandler.loadPerson({
          resp: resp
          context: @
          success: (gplusAttrs) ->
            existingUser = new User()
            existingUser.fetchGPlusUser(gplusAttrs.gplusID, gplusAttrs.email, {
              success: =>
                me.loginGPlusUser(gplusAttrs.gplusID, {
                  success: =>
                    application.tracker.identifyAfterNextPageLoad()
                    application.tracker.identify().finally(=>
                      loginNavigate(@subModalContinue)
                    )
                  error: @onGPlusLoginError
                })
              error: (res, jqxhr) =>
                if jqxhr.status is 409 and jqxhr.responseJSON.errorID and jqxhr.responseJSON.errorID is 'account-with-email-exists'
                  noty({ text: $.i18n.t('login.accounts_merge_confirmation'), layout: 'topCenter', type: 'info', buttons: [
                    { text: 'Yes', onClick: ($noty) ->
                      $noty.close()
                      me.loginGPlusUser(gplusAttrs.gplusID, {
                        data: { merge: true, email: gplusAttrs.email }
                        success: =>
                          application.tracker.identifyAfterNextPageLoad()
                          application.tracker.identify().finally(=>
                            loginNavigate(@subModalContinue)
                          )
                        error: @onGPlusLoginError
                      })
                    }, { text: 'No', onClick: ($noty) -> $noty.close() }]
                  })
                else
                  @onGPlusLoginError(res, jqxhr)
            })
        })
      error: (e) ->
        @onGPlusLoginError()
        e.message ||= "Google login failed: #{e.error} - #{e.details}" if e?.error and e?.details
        noty({text: e?.message or e?.details or e?.toString?() or 'Unknown Google login error', layout: 'topCenter', type: 'error', timeout: 5000, killer: false, dismissQueue: true})
    })

  onGPlusLoginError: =>
    btn = @$('#google-login-button')
    btn.find('.sign-in-blurb').text($.i18n.t('login.sign_in_with_gplus'))
    btn.attr('disabled', false)
    errors.showNotyNetworkError(arguments...) if arguments.length


  # Facebook

  onClickFacebookLoginButton: ->
    btn = @$('#facebook-login-btn')
    application.facebookHandler.connect({
      context: @
      success: ->
        btn.find('.sign-in-blurb').text($.i18n.t('login.logging_in'))
        btn.attr('disabled', true)
        application.facebookHandler.loadPerson({
          context: @
          success: (facebookAttrs) ->
            existingUser = new User()
            existingUser.fetchFacebookUser(facebookAttrs.facebookID, {
              success: =>
                me.loginFacebookUser(facebookAttrs.facebookID, {
                  success: =>
                    application.tracker.identifyAfterNextPageLoad()
                    application.tracker.identify().then(=>
                      loginNavigate(@subModalContinue)
                    )
                  error: @onFacebookLoginError
                })
              error: @onFacebookLoginError
            })
        })
    })

  onFacebookLoginError: =>
    btn = @$('#facebook-login-btn')
    btn.find('.sign-in-blurb').text($.i18n.t('login.sign_in_with_facebook'))
    btn.attr('disabled', false)
    errors.showNotyNetworkError(arguments...)


  # Clever

  onClickCleverSignupButton: ->
    if window.location.hostname in ['next.codecombat.com', 'localhost']
      cleverClientId = '943ece596555cac13fcc'
      redirectTo = 'https://next.codecombat.com/auth/login-clever'
      districtId = '5b2ad81a709e300001e2cd7a'  # Clever Library test district
    else  # prod
      cleverClientId = 'ffce544a7e02c0daabf2'
      redirectTo = 'https://codecombat.com/auth/login-clever'
    url = "https://clever.com/oauth/authorize?response_type=code&redirect_uri=#{encodeURIComponent(redirectTo)}&client_id=#{cleverClientId}"
    if districtId
      url += '&district_id=' + districtId
    window.open url, '_blank'


  openRecoverModal: (e) ->
    e.stopPropagation()
    @openModalView new RecoverModal()

  onHidden: ->
    super()
    @playSound 'game-menu-close'

formSchema = {
  type: 'object'
  properties: {
    emailOrUsername: {
      $or: [
        User.schema.properties.name
        User.schema.properties.email
      ]
    }
  }
  required: ['emailOrUsername', 'password']
}

loginNavigate = (subModalContinue) ->
  if window.nextURL
    window.location.href = window.nextURL
    return

  if not me.isAdmin()
    if me.isAPIClient()
        application.router.navigate('/api-dashboard', { trigger: true })
    else if me.isStudent()
      if features.chinaHome
        window.location.href = 'https://koudashijie.com/students'
        return
      application.router.navigate('/students', { trigger: true })
    else if me.isTeacher()
      if features.chinaHome
        window.location.href = 'https://koudashijie.com/students'
        return
      if me.isSchoolAdmin()
        application.router.navigate('/teachers/licenses', { trigger: true })
      else
        application.router.navigate('/teachers/classes', { trigger: true })
  else if subModalContinue
    storage.save('sub-modal-continue', subModalContinue)

  window.location.reload()
