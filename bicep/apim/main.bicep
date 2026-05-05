// APIM-export-artifact display names. Not secrets — just placeholder display
// strings for the default starter / unlimited product subscriptions and the
// Administrator user. The previous @secure() decorators were misleading: ARM
// export added them automatically but the values are non-sensitive.
param subscriptions_69c2f544f2ccf70039070001_displayName string = 'Subscription 1'
param subscriptions_69c2f544f2ccf70039070002_displayName string = 'Subscription 2'
param users_1_lastName string = 'Administrator'

// 2026-05-05: migrated Developer (apim-cliquepix-002) → Basic v2
// (apim-cliquepix-003) for SLA + v2 platform. The bicep symbol names retain
// the "_002_" suffix on purpose — renaming every parent reference would be a
// large cosmetic diff. The deployed name (this param) is what reaches Azure.
param service_apim_cliquepix_002_name string = 'apim-cliquepix-003'

resource service_apim_cliquepix_002_name_resource 'Microsoft.ApiManagement/service@2025-03-01-preview' = {
  name: service_apim_cliquepix_002_name
  location: 'East US'
  sku: {
    name: 'BasicV2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: 'gwhitley@xtend-ai.com'
    publisherName: 'Xtend-AI'
    notificationSenderEmail: 'apimgmt-noreply@mail.windowsazure.com'
    hostnameConfigurations: [
      {
        type: 'Proxy'
        hostName: '${service_apim_cliquepix_002_name}.azure-api.net'
        negotiateClientCertificate: false
        defaultSslBinding: true
        certificateSource: 'BuiltIn'
      }
    ]
    // customProperties (TLS cipher toggles) removed for v2 — classic-only,
    // ARM deploy fails on v2 if present. Per Microsoft Learn v2 unavailable-
    // features list ("Cipher configuration").
    // legacyPortalStatus / developerPortalStatus / releaseChannel removed —
    // also classic-only.
    virtualNetworkType: 'None'
    disableGateway: false
    apiVersionConstraint: {}
    publicNetworkAccess: 'Enabled'
  }
}

resource service_apim_cliquepix_002_name_cliquepix_v1 'Microsoft.ApiManagement/service/apis@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'cliquepix-v1'
  properties: {
    displayName: 'CliquePix API v1'
    apiRevision: '1'
    subscriptionRequired: false
    serviceUrl: 'https://func-cliquepix-fresh.azurewebsites.net/api'
    path: 'api'
    protocols: [
      'https'
    ]
    authenticationSettings: {
      oAuth2AuthenticationSettings: []
      openidAuthenticationSettings: []
    }
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    isCurrent: true
  }
}

// Echo API + all its operations / policies / product apiLinks were removed
// 2026-05-05 as part of the BasicV2 migration. Default APIM scaffolding,
// never used by Clique Pix. The cliquepix-v1 API below is the only real API.

resource service_apim_cliquepix_002_name_administrators 'Microsoft.ApiManagement/service/groups@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'administrators'
  properties: {
    displayName: 'Administrators'
    description: 'Administrators is a built-in group containing the admin email account provided at the time of service creation. Its membership is managed by the system.'
    type: 'system'
  }
}

resource service_apim_cliquepix_002_name_developers 'Microsoft.ApiManagement/service/groups@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'developers'
  properties: {
    displayName: 'Developers'
    description: 'Developers is a built-in group. Its membership is managed by the system. Signed-in users fall into this group.'
    type: 'system'
  }
}

resource service_apim_cliquepix_002_name_guests 'Microsoft.ApiManagement/service/groups@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'guests'
  properties: {
    displayName: 'Guests'
    description: 'Guests is a built-in group. Its membership is managed by the system. Unauthenticated users visiting the developer portal fall into this group.'
    type: 'system'
  }
}

resource service_apim_cliquepix_002_name_AccountClosedPublisher 'Microsoft.ApiManagement/service/notifications@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'AccountClosedPublisher'
}

resource service_apim_cliquepix_002_name_BCC 'Microsoft.ApiManagement/service/notifications@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'BCC'
}

resource service_apim_cliquepix_002_name_NewApplicationNotificationMessage 'Microsoft.ApiManagement/service/notifications@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'NewApplicationNotificationMessage'
}

resource service_apim_cliquepix_002_name_NewIssuePublisherNotificationMessage 'Microsoft.ApiManagement/service/notifications@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'NewIssuePublisherNotificationMessage'
}

resource service_apim_cliquepix_002_name_PurchasePublisherNotificationMessage 'Microsoft.ApiManagement/service/notifications@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'PurchasePublisherNotificationMessage'
}

resource service_apim_cliquepix_002_name_QuotaLimitApproachingPublisherNotificationMessage 'Microsoft.ApiManagement/service/notifications@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'QuotaLimitApproachingPublisherNotificationMessage'
}

resource service_apim_cliquepix_002_name_RequestPublisherNotificationMessage 'Microsoft.ApiManagement/service/notifications@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'RequestPublisherNotificationMessage'
}

resource service_apim_cliquepix_002_name_policy 'Microsoft.ApiManagement/service/policies@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'policy'
  properties: {
    value: '<!--\r\n    IMPORTANT:\r\n    - Policy elements can appear only within the <inbound>, <outbound>, <backend> section elements.\r\n    - Only the <forward-request> policy element can appear within the <backend> section element.\r\n    - To apply a policy to the incoming request (before it is forwarded to the backend service), place a corresponding policy element within the <inbound> section element.\r\n    - To apply a policy to the outgoing response (before it is sent back to the caller), place a corresponding policy element within the <outbound> section element.\r\n    - To add a policy position the cursor at the desired insertion point and click on the round button associated with the policy.\r\n    - To remove a policy, delete the corresponding policy statement from the policy document.\r\n    - Policies are applied in the order of their appearance, from the top down.\r\n-->\r\n<policies>\r\n  <inbound />\r\n  <backend>\r\n    <forward-request />\r\n  </backend>\r\n  <outbound />\r\n</policies>'
    format: 'xml'
  }
}

resource service_apim_cliquepix_002_name_default 'Microsoft.ApiManagement/service/portalconfigs@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'default'
  properties: {
    enableBasicAuth: true
    signin: {
      require: false
    }
    signup: {
      termsOfService: {
        requireConsent: false
      }
    }
    delegation: {
      delegateRegistration: false
      delegateSubscription: false
    }
    cors: {
      allowedOrigins: []
    }
    csp: {
      mode: 'disabled'
      reportUri: []
      allowedSources: []
    }
  }
}

// portalsettings/{delegation,signin,signup} removed for BasicV2 — Microsoft
// rejects them as 'MethodNotAllowedInPricingTier'. Clique Pix does not use
// the APIM developer portal anyway (clients hit api.clique-pix.com via
// Front Door → APIM gateway directly).

resource service_apim_cliquepix_002_name_starter 'Microsoft.ApiManagement/service/products@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'starter'
  properties: {
    displayName: 'Starter'
    description: 'Subscribers will be able to run 5 calls/minute up to a maximum of 100 calls/week.'
    subscriptionRequired: true
    approvalRequired: false
    subscriptionsLimit: 1
    state: 'published'
    authenticationType: []
  }
}

resource service_apim_cliquepix_002_name_unlimited 'Microsoft.ApiManagement/service/products@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'unlimited'
  properties: {
    displayName: 'Unlimited'
    description: 'Subscribers have completely unlimited access to the API. Administrator approval is required.'
    subscriptionRequired: true
    approvalRequired: true
    subscriptionsLimit: 1
    state: 'published'
    authenticationType: []
  }
}

// Built-in 'master' all-access subscription removed — its scope (the full
// service ID with trailing slash) is rejected by APIM REST as
// 'Subscription scope should be one of /apis, /apis/{apiId},
// /products/{productId}'. Clique Pix's cliquepix-v1 API has
// subscriptionRequired:false, so APIM subscriptions aren't used at all.

resource service_apim_cliquepix_002_name_AccountClosedDeveloper 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'AccountClosedDeveloper'
  properties: {
    subject: 'Thank you for using the $OrganizationName API!'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          On behalf of $OrganizationName and our customers we thank you for giving us a try. Your $OrganizationName API account is now closed.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Your $OrganizationName Team</p>\r\n    <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n    <p />\r\n  </body>\r\n</html>'
    title: 'Developer farewell letter'
    description: 'Developers receive this farewell email after they close their account.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_ApplicationApprovedNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'ApplicationApprovedNotificationMessage'
  properties: {
    subject: 'Your application $AppName is published in the application gallery'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          We are happy to let you know that your request to publish the $AppName application in the application gallery has been approved. Your application has been published and can be viewed <a href="http://$DevPortalUrl/Applications/Details/$AppId">here</a>.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n  </body>\r\n</html>'
    title: 'Application gallery submission approved (deprecated)'
    description: 'Developers who submitted their application for publication in the application gallery on the developer portal receive this email after their submission is approved.'
    parameters: [
      {
        name: 'AppId'
        title: 'Application id'
      }
      {
        name: 'AppName'
        title: 'Application name'
      }
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_ConfirmSignUpIdentityDefault 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'ConfirmSignUpIdentityDefault'
  properties: {
    subject: 'Please confirm your new $OrganizationName API account'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <meta charset="UTF-8" />\r\n    <title>Letter</title>\r\n  </head>\r\n  <body>\r\n    <table width="100%">\r\n      <tr>\r\n        <td>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'"></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you for joining the $OrganizationName API program! We host a growing number of cool APIs and strive to provide an awesome experience for API developers.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">First order of business is to activate your account and get you going. To that end, please click on the following link:</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a id="confirmUrl" href="$ConfirmUrl" style="text-decoration:none">\r\n              <strong>$ConfirmUrl</strong>\r\n            </a>\r\n          </p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">If clicking the link does not work, please copy-and-paste or re-type it into your browser\'s address bar and hit "Enter".</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n          </p>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n  </body>\r\n</html>'
    title: 'New developer account confirmation'
    description: 'Developers receive this email to confirm their e-mail address after they sign up for a new account.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'ConfirmUrl'
        title: 'Developer activation URL'
      }
      {
        name: 'DevPortalHost'
        title: 'Developer portal hostname'
      }
      {
        name: 'ConfirmQuery'
        title: 'Query string part of the activation URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_EmailChangeIdentityDefault 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'EmailChangeIdentityDefault'
  properties: {
    subject: 'Please confirm the new email associated with your $OrganizationName API account'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <meta charset="UTF-8" />\r\n    <title>Letter</title>\r\n  </head>\r\n  <body>\r\n    <table width="100%">\r\n      <tr>\r\n        <td>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'"></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">You are receiving this email because you made a change to the email address on your $OrganizationName API account.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Please click on the following link to confirm the change:</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a id="confirmUrl" href="$ConfirmUrl" style="text-decoration:none">\r\n              <strong>$ConfirmUrl</strong>\r\n            </a>\r\n          </p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">If clicking the link does not work, please copy-and-paste or re-type it into your browser\'s address bar and hit "Enter".</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n          </p>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n  </body>\r\n</html>'
    title: 'Email change confirmation'
    description: 'Developers receive this email to confirm a new e-mail address after they change their existing one associated with their account.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'ConfirmUrl'
        title: 'Developer confirmation URL'
      }
      {
        name: 'DevPortalHost'
        title: 'Developer portal hostname'
      }
      {
        name: 'ConfirmQuery'
        title: 'Query string part of the confirmation URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_InviteUserNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'InviteUserNotificationMessage'
  properties: {
    subject: 'You are invited to join the $OrganizationName developer network'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Your account has been created. Please follow the link below to visit the $OrganizationName developer portal and claim it:\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n      <a href="$ConfirmUrl">$ConfirmUrl</a>\r\n    </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n  </body>\r\n</html>'
    title: 'Invite user'
    description: 'An e-mail invitation to create an account, sent on request by API publishers.'
    parameters: [
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'ConfirmUrl'
        title: 'Confirmation link'
      }
      {
        name: 'DevPortalHost'
        title: 'Developer portal hostname'
      }
      {
        name: 'ConfirmQuery'
        title: 'Query string part of the confirmation link'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_NewCommentNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'NewCommentNotificationMessage'
  properties: {
    subject: '$IssueName issue has a new comment'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">This is a brief note to let you know that $CommenterFirstName $CommenterLastName made the following comment on the issue $IssueName you created:</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">$CommentText</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          To view the issue on the developer portal click <a href="http://$DevPortalUrl/issues/$IssueId">here</a>.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n  </body>\r\n</html>'
    title: 'New comment added to an issue (deprecated)'
    description: 'Developers receive this email when someone comments on the issue they created on the Issues page of the developer portal.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'CommenterFirstName'
        title: 'Commenter first name'
      }
      {
        name: 'CommenterLastName'
        title: 'Commenter last name'
      }
      {
        name: 'IssueId'
        title: 'Issue id'
      }
      {
        name: 'IssueName'
        title: 'Issue name'
      }
      {
        name: 'CommentText'
        title: 'Comment text'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_NewDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'NewDeveloperNotificationMessage'
  properties: {
    subject: 'Welcome to the $OrganizationName API!'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <meta charset="UTF-8" />\r\n    <title>Letter</title>\r\n  </head>\r\n  <body>\r\n    <h1 style="color:#000505;font-size:18pt;font-family:\'Segoe UI\'">\r\n          Welcome to <span style="color:#003363">$OrganizationName API!</span></h1>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Your $OrganizationName API program registration is completed and we are thrilled to have you as a customer. Here are a few important bits of information for your reference:</p>\r\n    <table width="100%" style="margin:20px 0">\r\n      <tr>\r\n            #if ($IdentityProvider == "Basic")\r\n            <td width="50%" style="height:40px;vertical-align:top;font-family:\'Segoe UI\';font-size:12pt">\r\n              Please use the following <strong>username</strong> when signing into any of the \${OrganizationName}-hosted developer portals:\r\n            </td><td style="vertical-align:top;font-family:\'Segoe UI\';font-size:12pt"><strong>$DevUsername</strong></td>\r\n            #else\r\n            <td width="50%" style="height:40px;vertical-align:top;font-family:\'Segoe UI\';font-size:12pt">\r\n              Please use the following <strong>$IdentityProvider account</strong> when signing into any of the \${OrganizationName}-hosted developer portals:\r\n            </td><td style="vertical-align:top;font-family:\'Segoe UI\';font-size:12pt"><strong>$DevUsername</strong></td>            \r\n            #end\r\n          </tr>\r\n      <tr>\r\n        <td style="height:40px;vertical-align:top;font-family:\'Segoe UI\';font-size:12pt">\r\n              We will direct all communications to the following <strong>email address</strong>:\r\n            </td>\r\n        <td style="vertical-align:top;font-family:\'Segoe UI\';font-size:12pt">\r\n          <a href="mailto:$DevEmail" style="text-decoration:none">\r\n            <strong>$DevEmail</strong>\r\n          </a>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best of luck in your API pursuits!</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n      <a href="http://$DevPortalUrl">$DevPortalUrl</a>\r\n    </p>\r\n  </body>\r\n</html>'
    title: 'Developer welcome letter'
    description: 'Developers receive this “welcome” email after they confirm their new account.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'DevUsername'
        title: 'Developer user name'
      }
      {
        name: 'DevEmail'
        title: 'Developer email'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'IdentityProvider'
        title: 'Identity Provider selected by Organization'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_NewIssueNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'NewIssueNotificationMessage'
  properties: {
    subject: 'Your request $IssueName was received'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you for contacting us. Our API team will review your issue and get back to you soon.</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Click this <a href="http://$DevPortalUrl/issues/$IssueId">link</a> to view or edit your request.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Best,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n  </body>\r\n</html>'
    title: 'New issue received (deprecated)'
    description: 'This email is sent to developers after they create a new topic on the Issues page of the developer portal.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'IssueId'
        title: 'Issue id'
      }
      {
        name: 'IssueName'
        title: 'Issue name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_PasswordResetByAdminNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'PasswordResetByAdminNotificationMessage'
  properties: {
    subject: 'Your password was reset'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <table width="100%">\r\n      <tr>\r\n        <td>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'"></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">The password of your $OrganizationName API account has been reset, per your request.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n                Your new password is: <strong>$DevPassword</strong></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Please make sure to change it next time you sign in.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n          </p>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n  </body>\r\n</html>'
    title: 'Password reset by publisher notification (Password reset by admin)'
    description: 'Developers receive this email when the publisher resets their password.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'DevPassword'
        title: 'New Developer password'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_PasswordResetIdentityDefault 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'PasswordResetIdentityDefault'
  properties: {
    subject: 'Your password change request'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <meta charset="UTF-8" />\r\n    <title>Letter</title>\r\n  </head>\r\n  <body>\r\n    <table width="100%">\r\n      <tr>\r\n        <td>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'"></p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">You are receiving this email because you requested to change the password on your $OrganizationName API account.</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Please click on the link below and follow instructions to create your new password:</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a id="resetUrl" href="$ConfirmUrl" style="text-decoration:none">\r\n              <strong>$ConfirmUrl</strong>\r\n            </a>\r\n          </p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">If clicking the link does not work, please copy-and-paste or re-type it into your browser\'s address bar and hit "Enter".</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">$OrganizationName API Team</p>\r\n          <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n          </p>\r\n        </td>\r\n      </tr>\r\n    </table>\r\n  </body>\r\n</html>'
    title: 'Password change confirmation'
    description: 'Developers receive this email when they request a password change of their account. The purpose of the email is to verify that the account owner made the request and to provide a one-time perishable URL for changing the password.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'ConfirmUrl'
        title: 'Developer new password instruction URL'
      }
      {
        name: 'DevPortalHost'
        title: 'Developer portal hostname'
      }
      {
        name: 'ConfirmQuery'
        title: 'Query string part of the instruction URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_PurchaseDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'PurchaseDeveloperNotificationMessage'
  properties: {
    subject: 'Your subscription to the $ProdName'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Greetings $DevFirstName $DevLastName!</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Thank you for subscribing to the <a href="http://$DevPortalUrl/product#product=$ProdId"><strong>$ProdName</strong></a> and welcome to the $OrganizationName developer community. We are delighted to have you as part of the team and are looking forward to the amazing applications you will build using our API!\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Below are a few subscription details for your reference:</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n      <ul>\r\n            #if ($SubStartDate != "")\r\n            <li style="font-size:12pt;font-family:\'Segoe UI\'">Start date: $SubStartDate</li>\r\n            #end\r\n            \r\n            #if ($SubTerm != "")\r\n            <li style="font-size:12pt;font-family:\'Segoe UI\'">Subscription term: $SubTerm</li>\r\n            #end\r\n          </ul>\r\n    </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n            Visit the developer <a href="http://$DevPortalUrl/profile">profile area</a> to manage your subscription and subscription keys\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">A couple of pointers to help get you started:</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n      <strong>\r\n        <a href="http://$DevPortalUrl/product#product=$ProdId">Learn about the API</a>\r\n      </strong>\r\n    </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The API documentation provides all information necessary to make a request and to process a response. Code samples are provided per API operation in a variety of languages. Moreover, an interactive console allows making API calls directly from the developer portal without writing any code.</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Happy hacking,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n    <a style="font-size:12pt;font-family:\'Segoe UI\'" href="http://$DevPortalUrl">$DevPortalUrl</a>\r\n  </body>\r\n</html>'
    title: 'New subscription activated'
    description: 'Developers receive this acknowledgement email after subscribing to a product.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'ProdId'
        title: 'Product ID'
      }
      {
        name: 'ProdName'
        title: 'Product name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'SubStartDate'
        title: 'Subscription start date'
      }
      {
        name: 'SubTerm'
        title: 'Subscription term'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_QuotaLimitApproachingDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'QuotaLimitApproachingDeveloperNotificationMessage'
  properties: {
    subject: 'You are approaching an API quota limit'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head>\r\n    <style>\r\n          body {font-size:12pt; font-family:"Segoe UI","Segoe WP","Tahoma","Arial","sans-serif";}\r\n          .alert { color: red; }\r\n          .child1 { padding-left: 20px; }\r\n          .child2 { padding-left: 40px; }\r\n          .number { text-align: right; }\r\n          .text { text-align: left; }\r\n          th, td { padding: 4px 10px; min-width: 100px; }\r\n          th { background-color: #DDDDDD;}\r\n        </style>\r\n  </head>\r\n  <body>\r\n    <p>Greetings $DevFirstName $DevLastName!</p>\r\n    <p>\r\n          You are approaching the quota limit on you subscription to the <strong>$ProdName</strong> product (primary key $SubPrimaryKey).\r\n          #if ($QuotaResetDate != "")\r\n          This quota will be renewed on $QuotaResetDate.\r\n          #else\r\n          This quota will not be renewed.\r\n          #end\r\n        </p>\r\n    <p>Below are details on quota usage for the subscription:</p>\r\n    <p>\r\n      <table>\r\n        <thead>\r\n          <th class="text">Quota Scope</th>\r\n          <th class="number">Calls</th>\r\n          <th class="number">Call Quota</th>\r\n          <th class="number">Bandwidth</th>\r\n          <th class="number">Bandwidth Quota</th>\r\n        </thead>\r\n        <tbody>\r\n          <tr>\r\n            <td class="text">Subscription</td>\r\n            <td class="number">\r\n                  #if ($CallsAlert == true)\r\n                  <span class="alert">$Calls</span>\r\n                  #else\r\n                  $Calls\r\n                  #end\r\n                </td>\r\n            <td class="number">$CallQuota</td>\r\n            <td class="number">\r\n                  #if ($BandwidthAlert == true)\r\n                  <span class="alert">$Bandwidth</span>\r\n                  #else\r\n                  $Bandwidth\r\n                  #end\r\n                </td>\r\n            <td class="number">$BandwidthQuota</td>\r\n          </tr>\r\n              #foreach ($api in $Apis)\r\n              <tr><td class="child1 text">API: $api.Name</td><td class="number">\r\n                  #if ($api.CallsAlert == true)\r\n                  <span class="alert">$api.Calls</span>\r\n                  #else\r\n                  $api.Calls\r\n                  #end\r\n                </td><td class="number">$api.CallQuota</td><td class="number">\r\n                  #if ($api.BandwidthAlert == true)\r\n                  <span class="alert">$api.Bandwidth</span>\r\n                  #else\r\n                  $api.Bandwidth\r\n                  #end\r\n                </td><td class="number">$api.BandwidthQuota</td></tr>\r\n              #foreach ($operation in $api.Operations)\r\n              <tr><td class="child2 text">Operation: $operation.Name</td><td class="number">\r\n                  #if ($operation.CallsAlert == true)\r\n                  <span class="alert">$operation.Calls</span>\r\n                  #else\r\n                  $operation.Calls\r\n                  #end\r\n                </td><td class="number">$operation.CallQuota</td><td class="number">\r\n                  #if ($operation.BandwidthAlert == true)\r\n                  <span class="alert">$operation.Bandwidth</span>\r\n                  #else\r\n                  $operation.Bandwidth\r\n                  #end\r\n                </td><td class="number">$operation.BandwidthQuota</td></tr>\r\n              #end\r\n              #end\r\n            </tbody>\r\n      </table>\r\n    </p>\r\n    <p>Thank you,</p>\r\n    <p>$OrganizationName API Team</p>\r\n    <a href="$DevPortalUrl">$DevPortalUrl</a>\r\n    <p />\r\n  </body>\r\n</html>'
    title: 'Developer quota limit approaching notification'
    description: 'Developers receive this email to alert them when they are approaching a quota limit.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'ProdName'
        title: 'Product name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'SubPrimaryKey'
        title: 'Primary Subscription key'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
      {
        name: 'QuotaResetDate'
        title: 'Quota reset date'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_RejectDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'RejectDeveloperNotificationMessage'
  properties: {
    subject: 'Your subscription request for the $ProdName'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          We would like to inform you that we reviewed your subscription request for the <strong>$ProdName</strong>.\r\n        </p>\r\n        #if ($SubDeclineReason == "")\r\n        <p style="font-size:12pt;font-family:\'Segoe UI\'">Regretfully, we were unable to approve it, as subscriptions are temporarily suspended at this time.</p>\r\n        #else\r\n        <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Regretfully, we were unable to approve it at this time for the following reason:\r\n          <div style="margin-left: 1.5em;"> $SubDeclineReason </div></p>\r\n        #end\r\n        <p style="font-size:12pt;font-family:\'Segoe UI\'"> We truly appreciate your interest. </p><p style="font-size:12pt;font-family:\'Segoe UI\'">All the best,</p><p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p><a style="font-size:12pt;font-family:\'Segoe UI\'" href="http://$DevPortalUrl">$DevPortalUrl</a></body>\r\n</html>'
    title: 'Subscription request declined'
    description: 'This email is sent to developers when their subscription requests for products requiring publisher approval is declined.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'SubDeclineReason'
        title: 'Reason for declining subscription'
      }
      {
        name: 'ProdName'
        title: 'Product name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_RequestDeveloperNotificationMessage 'Microsoft.ApiManagement/service/templates@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: 'RequestDeveloperNotificationMessage'
  properties: {
    subject: 'Your subscription request for the $ProdName'
    body: '<!DOCTYPE html >\r\n<html>\r\n  <head />\r\n  <body>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Dear $DevFirstName $DevLastName,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          Thank you for your interest in our <strong>$ProdName</strong> API product!\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">\r\n          We were delighted to receive your subscription request. We will promptly review it and get back to you at <strong>$DevEmail</strong>.\r\n        </p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">Thank you,</p>\r\n    <p style="font-size:12pt;font-family:\'Segoe UI\'">The $OrganizationName API Team</p>\r\n    <a style="font-size:12pt;font-family:\'Segoe UI\'" href="http://$DevPortalUrl">$DevPortalUrl</a>\r\n  </body>\r\n</html>'
    title: 'Subscription request received'
    description: 'This email is sent to developers to acknowledge receipt of their subscription requests for products requiring publisher approval.'
    parameters: [
      {
        name: 'DevFirstName'
        title: 'Developer first name'
      }
      {
        name: 'DevLastName'
        title: 'Developer last name'
      }
      {
        name: 'DevEmail'
        title: 'Developer email'
      }
      {
        name: 'ProdName'
        title: 'Product name'
      }
      {
        name: 'OrganizationName'
        title: 'Organization name'
      }
      {
        name: 'DevPortalUrl'
        title: 'Developer portal URL'
      }
    ]
  }
}

resource service_apim_cliquepix_002_name_1 'Microsoft.ApiManagement/service/users@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_resource
  name: '1'
  properties: {
    firstName: 'Administrator'
    email: 'gwhitley@xtend-ai.com'
    state: 'active'
    identities: [
      {
        provider: 'Azure'
        id: 'gwhitley@xtend-ai.com'
      }
    ]
    lastName: users_1_lastName
  }
}

resource service_apim_cliquepix_002_name_cliquepix_v1_auth_verify 'Microsoft.ApiManagement/service/apis/operations@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_cliquepix_v1
  name: 'auth-verify'
  properties: {
    displayName: 'Auth Verify'
    method: 'POST'
    urlTemplate: '/auth/verify'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

resource service_apim_cliquepix_002_name_cliquepix_v1_catch_all_delete 'Microsoft.ApiManagement/service/apis/operations@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_cliquepix_v1
  name: 'catch-all-delete'
  properties: {
    displayName: 'DELETE catch-all'
    method: 'DELETE'
    urlTemplate: '/*'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

resource service_apim_cliquepix_002_name_cliquepix_v1_catch_all_get 'Microsoft.ApiManagement/service/apis/operations@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_cliquepix_v1
  name: 'catch-all-get'
  properties: {
    displayName: 'GET catch-all'
    method: 'GET'
    urlTemplate: '/*'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

resource service_apim_cliquepix_002_name_cliquepix_v1_catch_all_patch 'Microsoft.ApiManagement/service/apis/operations@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_cliquepix_v1
  name: 'catch-all-patch'
  properties: {
    displayName: 'PATCH catch-all'
    method: 'PATCH'
    urlTemplate: '/*'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

resource service_apim_cliquepix_002_name_cliquepix_v1_catch_all_post 'Microsoft.ApiManagement/service/apis/operations@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_cliquepix_v1
  name: 'catch-all-post'
  properties: {
    displayName: 'POST catch-all'
    method: 'POST'
    urlTemplate: '/*'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

resource service_apim_cliquepix_002_name_cliquepix_v1_catch_all_put 'Microsoft.ApiManagement/service/apis/operations@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_cliquepix_v1
  name: 'catch-all-put'
  properties: {
    displayName: 'PUT catch-all'
    method: 'PUT'
    urlTemplate: '/*'
    templateParameters: []
    responses: []
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

// Echo operations (6 — create-resource, modify-resource, remove-resource,
// retrieve-header-only, retrieve-resource, retrieve-resource-cached) and
// their 3 attached operation policies were removed 2026-05-05 as part of
// the BasicV2 migration. The retrieve-resource-cached op had a
// <cache-lookup>/<cache-store> policy whose v2 syntax differs slightly —
// not relevant since the entire echo-api surface is gone.

resource service_apim_cliquepix_002_name_cliquepix_v1_upload_url 'Microsoft.ApiManagement/service/apis/operations@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_cliquepix_v1
  name: 'upload-url'
  properties: {
    displayName: 'Get Upload URL'
    method: 'POST'
    urlTemplate: '/events/{eventId}/photos/upload-url'
    templateParameters: [
      {
        name: 'eventId'
        type: 'string'
        required: true
        values: []
      }
    ]
    responses: []
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

// API-scope policy for cliquepix-v1. Source of truth is apim_policy.xml at
// repo root — loaded at compile time via loadTextContent so edits flow into
// the next bicep deploy automatically. The 6-incident history + the
// rate-limit prohibition live in apim_policy.xml's in-file comment.
// Pre-migration the XML was duplicated inline here (drift had occurred — the
// inline copy held the OLD 4-incident comment from 2026-04-27 while
// apim_policy.xml had the 6-incident comment as of 2026-05-05). Consolidated
// 2026-05-05 alongside the BasicV2 migration to eliminate the duplication.
resource service_apim_cliquepix_002_name_cliquepix_v1_policy 'Microsoft.ApiManagement/service/apis/policies@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_cliquepix_v1
  name: 'policy'
  properties: {
    value: loadTextContent('../../apim_policy.xml')
    format: 'xml'
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

// System-group user memberships (administrators / developers) removed —
// APIM rejects them with 'System group membership cannot be changed'.
// The Administrator user is auto-added to the administrators system group
// at service creation time.

// Echo API product/apis links removed alongside the echo-api itself
// (BasicV2 migration, 2026-05-05).

// Six service/products/groups associations (starter + unlimited × admins,
// developers, guests) removed — APIM auto-creates these system-product↔
// system-group links at service creation. Re-declaring them in bicep would
// fail with 'Link already exists between specified Product and Group'.
// Verified live state on apim-cliquepix-003 already has all six.

resource service_apim_cliquepix_002_name_starter_policy 'Microsoft.ApiManagement/service/products/policies@2025-03-01-preview' = {
  parent: service_apim_cliquepix_002_name_starter
  name: 'policy'
  properties: {
    value: '<policies>\r\n  <inbound>\r\n    <base />\r\n  </inbound>\r\n  <backend>\r\n    <base />\r\n  </backend>\r\n  <outbound>\r\n    <base />\r\n  </outbound>\r\n  <on-error>\r\n    <base />\r\n  </on-error>\r\n</policies>'
    format: 'xml'
  }
  dependsOn: [
    service_apim_cliquepix_002_name_resource
  ]
}

// REMOVED 2026-05-05 — incident #6: 6 operation-scope <rate-limit-by-key>
// resources (auth-verify 30/60, upload-url 10/60, catch-all-{delete,patch,post,put}
// 30/60, all keyed on JWT subject) were 429-blocking sign-ins because the 5-layer
// Entra refresh defense + verify-in-background + AuthInterceptor 401 retry can
// produce >30 calls/60s for a single user during a sign-in storm. They directly
// contradicted the API-scope policy comment above which forbids rate-limit-by-key
// on Developer tier. Live APIM was cleaned via az rest DELETE on the matching
// .../apis/cliquepix-v1/operations/{op}/policies/policy paths; bicep is now in
// sync. Operations themselves (URL templates) are unaffected — they're declared
// elsewhere in this file and continue to route. Without these policy attachments,
// each operation falls through to the API-scope policy (clean: <base/> + CORS).
// Backup of prior policies: C:\Users\genew\AppData\Local\Temp\apim-bak-20260505-1327\
// See apim_policy.xml in-file comment, docs/DEPLOYMENT_STATUS.md, and
// docs/BETA_OPERATIONS_RUNBOOK.md §2 for the full incident history (#1-#6).

// Echo API operation policies (3 — create-resource, retrieve-header-only,
// retrieve-resource-cached) and the newer-form product/apiLinks (2 — starter
// + unlimited) removed alongside echo-api itself (BasicV2 migration,
// 2026-05-05). The retrieve-resource-cached policy used cache-lookup +
// cache-store with vary-by-header — v2 policy syntax differs slightly here,
// but moot because the entire echo surface is gone.

// Six product/groupLinks resources removed — APIM rejects them with
// 'Link already exists between specified Product and Group' because the
// service auto-creates these system-product↔system-group links at service
// creation. They cannot be redeclared in IaC.
//
// Two product subscriptions (...69070001, ...69070002) removed — their
// scope (full product resource ID) is rejected by APIM with
// 'Subscription scope should be one of /apis, /apis/{apiId},
// /products/{productId}'. Clique Pix does not use APIM subscriptions
// (cliquepix-v1 has subscriptionRequired:false), so removing them
// has zero functional impact.
