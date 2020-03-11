# == class: keystone::federation::openidc [70/1473]
#
# == Parameters
#
# [*keystone_url*]
#  (Required) URL to keystone endpoint.
#
# [*methods*]
#  A list of methods used for authentication separated by comma or an array.
#  The allowed values are: 'external', 'password', 'token', 'oauth1', 'saml2',
#  and 'openid'
#  (Required) (string or array value).
#  Note: The external value should be dropped to avoid problems.
#
# [*idp_name*]
#  The name name associated with the IdP in Keystone.
#  (Required) String value.
#
# [*openidc_provider_metadata_url*]
#  The url that points to your OpenID Connect metadata provider
#  (Required) String value.
#
# [*openidc_client_id*]
#  The client ID to use when handshaking with your OpenID Connect provider
#  (Required) String value.
#
# [*openidc_client_secret*]
#  The client secret to use when handshaking with your OpenID Connect provider
#  (Required) String value.
#
# [*openidc_crypto_passphrase*]
#  Secret passphrase to use when encrypting data for OpenID Connect handshake
#  (Optional) String value.
#  Defaults to 'openstack'
#
# [*openidc_response_type*]
#  Response type to be expected from the OpenID Connect provider.
#  (Optional) String value.
#  Defaults to 'id_token'
#
# [*openidc_cache_type*]
#  (Optional) mod_auth_openidc cache type.  Can be any cache type
#  supported by mod_auth_openidc (shm, file, memcache, redis).
#  Defaults to undef.
#
# [*openidc_cache_shm_max*]
#  (Optional) The maximum number of name/value pair entries that can
#  be cached when using the 'shm' cache type. Defaults to undef.
#
# [*openidc_cache_shm_entry_size*]
#  (Optional) The maximum size for a single shm cache entry in bytes
#  with a minimum of 8464 bytes. Defaults to undef.
#
# [*openidc_cache_dir*]
#  (Optional) Directory that holds cache files; must be writable
#  for the Apache process/user. Defaults to undef.
#
# [*openidc_cache_clean_interval*]
#  (Optional) Cache file clean interval in seconds (only triggered
#  on writes). Defaults to undef.
#
# [*openidc_enable_oauth*]
#  (Optional) Set to true to enable oauthsupport.
#  Defaults to false.
#
# [*openidc_introspection_endpoint*]
#  (Required if oauth is enabled and configured for introspection)
#  OAuth introspection endpoint url.
#  Defaults to undef.
#
# [*openidc_verify_jwks_uri*]
#  (Required if oauth is enabled and configured for JWKS based validation)
#  The JWKS URL on which the Identity Provider
#  publishes the keys used to sign its JWT access tokens.
#  Defaults to undef.
#
# [*openidc_verify_method*]
#  (Optional) The method used to verify OAuth tokens.
#  Must be one of introspection or jwks
#  Defaults to introspection
#
# [*memcached_servers*]
#  (Optional) A list of memcache servers. Defaults to undef.
#
# [*redis_server*]
#  (Optional) Specifies the Redis server used for caching as
#  <hostname>[:<port>]. Defaults to undef.
#
# [*redis_password*]
#  (Optional) Password to be used if the Redis server requires
#  authentication. When not specified, no authentication is
#  performed. Defaults to undef.
#
# [*remote_id_attribute*]
#  (Optional) Value to be used to obtain the entity ID of the Identity
#  Provider from the environment.
#  Defaults to undef.
#
# [*template_order*]
#  This number indicates the order for the concat::fragment that will apply
#  the shibboleth configuration to Keystone VirtualHost. The value should
#  The value should be greater than 330 an less then 999, according to:
#  https://github.com/puppetlabs/puppetlabs-apache/blob/master/manifests/vhost.pp
#  The value 330 corresponds to the order for concat::fragment  "${name}-filters"
#  and "${name}-limits".
#  The value 999 corresponds to the order for concat::fragment "${name}-file_footer".
#  (Optional) Defaults to 331.
#
# [*package_ensure*]
#  (Optional) Desired ensure state of packages.
#  accepts latest or specific versions.
#  Defaults to present.
#
class keystone::federation::openidc (
  $keystone_url,
  $methods,
  $idp_name,
  $openidc_provider_metadata_url,
  $openidc_client_id,
  $openidc_client_secret,
  $openidc_crypto_passphrase      = 'openstack',
  $openidc_response_type          = 'id_token',
  $openidc_cache_type             = undef,
  $openidc_cache_shm_max          = undef,
  $openidc_cache_shm_entry_size   = undef,
  $openidc_cache_dir              = undef,
  $openidc_cache_clean_interval   = undef,
  $openidc_enable_oauth           = false,
  $openidc_introspection_endpoint = undef,
  $openidc_verify_jwks_uri        = undef,
  $openidc_verify_method          = 'introspection',
  $memcached_servers              = undef,
  $redis_server                   = undef,
  $redis_password                 = undef,
  $remote_id_attribute            = undef,
  $template_order                 = 331,
  $package_ensure                 = present,
) {

  include ::apache
  include ::keystone::deps
  include ::keystone::params

  if !($openidc_verify_method in ['introspection', 'jwks']) {
    fail('Unsupported token verification method.' +
        '  Must be one of "introspection" or "jwks"')
  }

  if ($openidc_verify_method == 'introspection') {
    if $openidc_enable_oauth and !$openidc_introspection_endpoint {
      fail('You must set openidc_introspection_endpoint when enabling oauth support' +
          ' and introspection.')
    }
  } elsif ($openidc_verify_method == 'jwks') {
    if $openidc_enable_oauth and !$openidc_verify_jwks_uri {
      fail('You must set openidc_verify_jwks_uri when enabling oauth support' +
          ' and local signature verification using a JWKS URL')
    }
  }

  $memcached_servers_real = join(any2array($memcached_servers), ' ')

  # Note: if puppet-apache modify these values, this needs to be updated
  if $template_order <= 330 or $template_order >= 999 {
    fail('The template order should be greater than 330 and less than 999.')
  }

  if ('external' in $methods ) {
    fail('The external method should be dropped to avoid any interference with openid.')
  }

  if !('openid' in $methods ) {
    fail('Methods should contain openid as one of the auth methods.')
  }

  keystone_config {
    'auth/methods': value  => join(any2array($methods),',');
    'auth/openid':  ensure => absent;
  }

  if $remote_id_attribute {
    keystone_config {
      'openid/remote_id_attribute': value => $remote_id_attribute;
    }
  }

  ensure_packages([$::keystone::params::openidc_package_name], {
    ensure => $package_ensure,
    tag    => 'keystone-support-package',
  })

  concat::fragment { 'configure_openidc_keystone':
    target  => "${keystone::wsgi::apache::priority}-keystone_wsgi.conf",
    content => template('keystone/openidc.conf.erb'),
    order   => $template_order,
  }
}
