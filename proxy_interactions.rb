module ProxyInteractions
  def build_params(env)
    headers = env['client-headers'] #.merge("Host" => 'dev-api.dtime.com')
    should_prefetch = env.params["prefetch"]
    params = {:prefetch => should_prefetch, :head => headers, :query => env.params}

    # Strip/add body params
    case(env[Goliath::Request::REQUEST_METHOD])
      when 'GET', 'OPTIONS', 'HEAD', 'DELETE'
        params[:head].delete("Content-Length")
        params.delete(:body)
      when 'POST', 'PUT', 'PATCH'
        params.merge!(:body => env[Goliath::Request::RACK_INPUT].read)
      else p "UNKNOWN METHOD #{env[Goliath::Request::REQUEST_METHOD]}"
    end
    puts [ env[Goliath::Request::REQUEST_METHOD], env[Goliath::Request::REQUEST_PATH], headers, env.params ].inspect
    params
  end

  def trigger_request(url, params)
    req = EM::HttpRequest.new(url)
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
    resp
  end

  def build_response(resp, opts = {})
    # if opts[:prefetch]
    response_headers = {}
    content_type = :text
    resp.response_header.each_pair do |k, v|
      # Skip internal negotiation headers
      next if k == "CONNECTION"
      next if k == "TRANSFER_ENCODING"
      next if k == "CONTENT_LENGTH"
      if k == "CONTENT_TYPE"
        content_type = case v
        when /json/
          :json
        else
          :text
        end
      end
      response_headers[to_http_header(k)] = v
    end
    # record(process_time, resp, env['client-headers'], response_headers)
    #
    #
    #

    if content_type == :json
      _response = rewrite_response(resp.response)
      _response = Yajl::Parser.new.parse(_response)
      _response = prefetch_with(_response, opts) if resp.response_header.status == 200

      _response = Yajl::Encoder.new.encode(_response)
    else
      _response = resp.response
    end

    [resp.response_header.status, response_headers, _response]
  end

  def prefetch_with(response, opts)
    return response unless opts[:prefetch]
    return response unless response.is_a?(Hash)
    return response unless response["_links"].is_a?(Hash)


    prefetching = []
    response["_embedded"].each do |k,v|
      if opts[:prefetch].include?(k)
        if v.is_a?(Hash)
          prefetching << [k, v["_links"]["self"]["href"]]
        else
          v.each do |v|
            prefetching << [k, v["_links"]["self"]["href"]]
          end
        end
      end
    end

    concurrency = 2
    prefetch_results = {}

    start_time = Time.now.to_f
    EM::Synchrony::FiberIterator.new(prefetching, concurrency).each do |(rel, url)|
      puts ["Prefetching #{rel} => #{url}"]
      resp = EventMachine::HttpRequest.new(url).get
      _response = rewrite_response(resp.response)
      resp_remapped = Yajl::Parser.new.parse(_response)
      if prefetch_results[rel] && prefetch_results[rel].is_a?(Array)
        prefetch_results[rel] << resp_remapped
      elsif prefetch_results[rel]
        prefetch_results[rel] = [prefetch_results[rel]]
        prefetch_results[rel] << resp_remapped
      else
        prefetch_results[rel] = resp_remapped
      end
    end

    prefetch_results.each do |k, v|
      response["_embedded"][k] = v
    end

    process_time = Time.now.to_f - start_time
    puts "Built embedded results in #{process_time}"

    response
  end

  # Need to convert from the CONTENT_TYPE we'll get back from the server
  # to the normal Content-Type header
  def to_http_header(k)
    k.downcase.split('_').collect { |e| e.capitalize }.join('-')
  end

  def rewrite_response(string)
    string.gsub(ENV['PROXY_TO'], ENV['PROXY_URL']
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

end
