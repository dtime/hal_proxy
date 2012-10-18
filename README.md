Reachably HAL API Proxy
================

Experiments with proxying all api requests through another app...

What it does:

If you send param of `prefetch=item`, and the response looks like HAL, it will fetch a full representation of the object at `_embedded[item]` and replace the current representation with whatever is the result of a GET `_embedded[item][_links][self]`.

This is based on an original concept seen in: http://vimeo.com/49609648

All other requests will pass through to the original app you point this proxy to, rewriting all urls in the response to hit the proxy.


set ENV['PROXY\_TARGET'] && ENV['PROXY\_URL']



Motivations
------------

(why?)

* put analytics here
* rate limiting logic: https://github.com/postrank-labs/goliath/blob/master/examples/auth\_and\_rate\_limit.rb
* embed at this level - composing smaller already cached components, rather
  than fresh renders

Starting:

ruby application.rb -p 9293

