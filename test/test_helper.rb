# set before using Bundler
ENV['RACK_ENV'] = 'test'

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/autorun'
require 'minitest/spec'
require 'minitest-spec-context'
require 'rack/test'
require 'mocha/setup'
require 'delorean'

# seed the environment
ENV['HEROKU_AUTH_URL'] = 'https://auth.example.org'

require_relative '../lib/heroku/bouncer'

OmniAuth.config.test_mode = true

class MiniTest::Spec

  # Embedding app

  def app_with_bouncer(&bouncer_config_block)
    bouncer_config = default_bouncer_config
    bouncer_config.merge!(bouncer_config_block.call) if bouncer_config_block
    Sinatra.new do
      use Rack::Session::Cookie, domain: MiniTest::Spec.app_host, secret: 'cde0e7ee63e9cb2edd04d8284961b28a6b6f6521f05d2094633dfbd00519fabaafae3b6ba3e92d9fe0770ea5a4f9a9e6be597cdcafbcfba12ea12b25508861fd'
      use Heroku::Bouncer, bouncer_config
      get '/:whatever' do
        params['whatever'] || 'root'
      end
    end
  end

  def default_bouncer_config
    {
      oauth: { id: '46307a2b-0397-4739-b2b7-2f67d1cff597', secret: '46307a2b-0397-4739-b2b7-2f67d1cff597' },
      secret: 'cde0e7ee63e9cb2edd04d8284961b28a6b6f6521f05d2094633dfbd00519fabaafae3b6ba3e92d9fe0770ea5a4f9a9e6be597cdcafbcfba12ea12b25508861fd'
    }
  end

  def self.app_host
    Rack::Test::DEFAULT_HOST
  end

  def app_host
    self.class.app_host
  end

  def app
    @app
  end

  def follow_successful_oauth!(fetched_user_info = {})
    # /auth/heroku (OAuth dance starts)
    OmniAuth.config.mock_auth[:heroku] = OmniAuth::AuthHash.new(provider: 'heroku', credentials: {token:'12345', refresh_token:'67890'})
    assert_equal "http://#{app_host}/auth/heroku", last_response.location, "The user didn't trigger the OmniAuth authentication"
    follow_redirect!

    # stub the user info that will be fetched from Heroku's API with the token returned with the authentication
    fetched_user_info = default_fetched_user_info.merge!(fetched_user_info)
    Heroku::Bouncer::Middleware.any_instance.stubs(:fetch_user).returns(fetched_user_info)

    # /auth/callback (OAuth dance finishes)
    assert last_response.location.include?('/auth/heroku/callback'), "The authentication didn't trigger the callback"
    assert 302, last_response.status
    follow_redirect!
  end

  def default_fetched_user_info
    { 'email' => 'joe@a.com', 'id' => 'uid_123@heroku.com', 'allow_tracking' => true, 'oauth_token' => '12345' }
  end

  def assert_redirected_to_path(path)
    assert 302, last_response.status
    assert_equal path, URI.parse(last_response.location).path, 'Missing redirection to #{path}'
  end

  def assert_requires_authentication
    assert_equal "http://#{app_host}/auth/heroku", last_response.location, "Authentication expected, wasn't required"
  end

end
