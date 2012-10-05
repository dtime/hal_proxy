require 'rubygems' unless defined?(Gem)
require 'bundler/setup'
require 'goliath'
# require 'em-mongo'
require 'em-http'
require 'yajl'
require 'em-synchrony/em-http'

class App < Goliath::API
  use Goliath::Rack::Params


  def on_headers(env, headers)
    env['client-headers'] = headers.merge("Host" => 'localhost:9292')
    env.logger.info 'proxying new request: ' + headers.inspect
  end

  def response(env)
    start_time = Time.now.to_f

    headers = env['client-headers'] #.merge("Host" => 'dev-api.dtime.com')
    params = {:head => headers, :query => env.params}
    puts [ headers, env.params, env[Goliath::Request::REQUEST_PATH]  ].inspect
    req = EM::HttpRequest.new("http://localhost:9292#{env[Goliath::Request::REQUEST_PATH]}")
    resp = case(env[Goliath::Request::REQUEST_METHOD])
      when 'GET'  then req.get(params[:head].merge("Content-Length" => nil))
      when 'POST' then req.post(params.merge(:body => env[Goliath::Request::RACK_INPUT].read))
      when 'PUT'  then req.put(params.merge(:body => env[Goliath::Request::RACK_INPUT].read))
      when 'HEAD' then req.head(params)
      when 'OPTIONS' then req.options(params)
      when 'DELETE' then req.delete(params)
      else p "UNKNOWN METHOD #{env[Goliath::Request::REQUEST_METHOD]}"
    end

    process_time = Time.now.to_f - start_time

    response_headers = {}
    resp.response_header.each_pair do |k, v|
      # Skip internal negotiation headers
      next if k == "CONNECTION"
      next if k == "TRANSFER_ENCODING"
      next if k == "CONTENT_LENGTH"
      response_headers[to_http_header(k)] = v
    end

    # record(process_time, resp, env['client-headers'], response_headers)
    #
    #
    #
    _response = Yajl::Parser.new.parse(resp.response)
    _response = remap_response(_response)

    [resp.response_header.status, response_headers, Yajl::Encoder.new.encode(_response)]
  end

  def remap_response(hash)
    if hash.is_a?(Array)
      hash = hash.map do |h|
        remap_response(h)
      end
    end
    if hash.respond_to?(:has_key?) && hash.has_key?("href") && hash.has_key?("uri")
      hash["href"] = "http://localhost:9293#{hash["uri"]}"
    elsif hash.respond_to?(:has_key?)
      hash.each do |k,v|
        hash[k] = remap_response(v)
      end
    end
    hash
  end

  # Need to convert from the CONTENT_TYPE we'll get back from the server
  # to the normal Content-Type header
  def to_http_header(k)
    k.downcase.split('_').collect { |e| e.capitalize }.join('-')
  end

  # Write the request information into mongo
  def record(process_time, resp, client_headers, response_headers)
    e = env
    e.trace('http_log_record')
    EM.next_tick do
      doc = {
        request: {
          http_method: e[Goliath::Request::REQUEST_METHOD],
          path: e[Goliath::Request::REQUEST_PATH],
          headers: client_headers,
          params: e.params
        },
        response: {
          status: resp.response_header.status,
          length: resp.response.length,
          headers: response_headers,
          body: resp.response
        },
        process_time: process_time,
        date: Time.now.to_i
      }

      if e[Goliath::Request::RACK_INPUT]
        doc[:request][:body] = e[Goliath::Request::RACK_INPUT].read
      end

      e.mongo.insert(doc)
    end
  end
end
