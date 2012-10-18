require 'rubygems' unless defined?(Gem)
require 'bundler/setup'
require 'goliath'
# require 'em-mongo'
require 'em-http'
require 'yajl'
require 'em-synchrony/em-http'
require 'em-synchrony/fiber_iterator'
require './proxy_interactions'

class App < Goliath::API
  use Goliath::Rack::Params
  include ProxyInteractions


  def on_headers(env, headers)
    host = (ENV['PROXY_TO'] || 'http://localhost:9292').gsub(/^https?:\/\//, '')
    env['client-headers'] = headers.merge("Host" => host)
    env.logger.info 'proxying new request: ' + headers.inspect
  end

  def response(env)
    start_time = Time.now.to_f

    params = build_params(env)

    host = ENV['PROXY_TO'] || 'http://localhost:9292'
    url = "#{host}#{env[Goliath::Request::REQUEST_PATH]}"
    resp = trigger_request(url, params)
    process_time = Time.now.to_f - start_time
    build_response(resp, params)
  end


  # Write the request information into mongo
  # def record(process_time, resp, client_headers, response_headers)
    # e = env
    # e.trace('http_log_record')
    # EM.next_tick do
      # doc = {
        # request: {
          # http_method: e[Goliath::Request::REQUEST_METHOD],
          # path: e[Goliath::Request::REQUEST_PATH],
          # headers: client_headers,
          # params: e.params
        # },
        # response: {
          # status: resp.response_header.status,
          # length: resp.response.length,
          # headers: response_headers,
          # body: resp.response
        # },
        # process_time: process_time,
        # date: Time.now.to_i
      # }

      # if e[Goliath::Request::RACK_INPUT]
        # doc[:request][:body] = e[Goliath::Request::RACK_INPUT].read
      # end

      # e.mongo.insert(doc)
    # end
  # end
end
