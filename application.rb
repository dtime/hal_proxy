require 'rubygems' unless defined?(Gem)
require 'bundler/setup'
require 'goliath'
# require 'em-mongo'
require 'em-http'
require 'yajl'
require 'em-synchrony/em-http'
module EventMachine
  module HTTPMethods
     %w[options patch].each do |type|
       class_eval %[
         alias :a#{type} :#{type}
         def #{type}(options = {}, &blk)
           f = Fiber.current

           conn = setup_request(:#{type}, options, &blk)
           if conn.error.nil?
             conn.callback { f.resume(conn) }
             conn.errback  { f.resume(conn) }

             Fiber.yield
           else
             conn
           end
         end
      ]
    end
  end
end

class App < Goliath::API
  use Goliath::Rack::Params


  def on_headers(env, headers)
    host = (ENV['PROXY_TO'] || 'http://localhost:9292').gsub(/^https?:\/\//, '')
    env['client-headers'] = headers.merge("Host" => host)
    env.logger.info 'proxying new request: ' + headers.inspect
  end

  def response(env)
    start_time = Time.now.to_f

    headers = env['client-headers'] #.merge("Host" => 'dev-api.dtime.com')
    params = {:head => headers, :query => env.params}
    host = ENV['PROXY_TO'] || 'http://localhost:9292'
    req = EM::HttpRequest.new("#{host}#{env[Goliath::Request::REQUEST_PATH]}")

    # Strip/add body
    case(env[Goliath::Request::REQUEST_METHOD])
      when 'GET', 'OPTIONS', 'HEAD'
        params[:head].delete("Content-Length")
        params.delete(:body)
      when 'POST', 'PUT', 'DELETE'
        params.merge!(:body => env[Goliath::Request::RACK_INPUT].read)
      else p "UNKNOWN METHOD #{env[Goliath::Request::REQUEST_METHOD]}"
    end

    puts [ env[Goliath::Request::REQUEST_METHOD], env[Goliath::Request::REQUEST_PATH], headers, env.params, params[:body]  ].inspect

    resp = case(env[Goliath::Request::REQUEST_METHOD])
      when 'GET' then req.get(params)
      when 'POST' then req.post(params)
      when 'PUT'  then req.put(params)
      when 'HEAD' then req.head(params)
      when 'OPTIONS' then req.options(params)
      when 'PATCH' then req.patch(params)
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
      proxy_host = ENV['PROXY_URL'] || 'http://localhost:9293'
      hash["href"] = "#{proxy_host}#{hash["uri"]}"
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
