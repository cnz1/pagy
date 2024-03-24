# frozen_string_literal: true

# Self-contained sinatra app to play with the pagy styles in the browser

# USAGE
#    pagy demo
# ...point your browser to http://0.0.0.0:8000

# Help:
#    pagy -h

VERSION = '7.0.11'

require 'bundler/inline'
gemfile true do
  source 'https://rubygems.org'
  gem 'oj'
  gem 'puma'
  gem 'rouge'
  gem 'sinatra'
  gem 'sinatra-contrib'
end

# pagy initializer
STYLES = { pagy:        { extra: 'pagy', prefix: '' },
           bootstrap:   {},
           bulma:       {},
           foundation:  {},
           materialize: {},
           semantic:    {},
           tailwind:    { extra: 'pagy', prefix: '' },
           uikit:       {} }.freeze

STYLES.each_key do |style|
  require "pagy/extras/#{STYLES[style][:extra] || style}"
end
require 'pagy/extras/items'
require 'pagy/extras/trim'
Pagy::DEFAULT[:trim_extra] = false         # opt-in trim
Pagy::DEFAULT[:size]       = [1, 4, 4, 1]  # old size default

# sinatra setup
require 'sinatra/base'

# sinatra application
class PagyDemo < Sinatra::Base
  configure do
    enable :inline_templates
  end

  include Pagy::Backend

  get '/' do
    redirect '/pagy'
  end

  get '/template' do
    collection = MockCollection.new
    @pagy, @records = pagy(collection, trim_extra: params['trim'])

    erb :template, locals: { pagy: @pagy, style: 'pagy' }
  end

  get('/javascripts/:file') do
    content_type 'application/javascript'
    send_file Pagy.root.join('javascripts', params[:file])
  end

  get('/stylesheets/:file') do
    content_type 'text/css'
    send_file Pagy.root.join('stylesheets', params[:file])
  end

  # one route/action per style
  STYLES.each_key do |style|
    prefix = STYLES[style][:prefix] || "_#{style}"

    get("/#{style}/?:trim?") do
      collection = MockCollection.new
      @pagy, @records = pagy(collection, trim_extra: params['trim'])

      erb :helpers, locals: { style:, prefix: }
    end
  end

  # We store the template in a constant instead of writing it inline, so we can highlight it more easily
  TEMPLATE = <<~ERB
    <%# IMPORTANT: use '<%== ... ' instead of '<%= ... ' if you run this in rails %>

    <%# The a variable below is set to a lambda that generates the a tag %>
    <%# Usage: a_tag = a.(page_number, text, classes: nil, aria_label: nil) %>
    <% a = pagy_anchor(pagy) %>
    <nav class="pagy nav" aria-label="Pages">
      <%# Previous page link %>
      <% if pagy.prev %>
          <%= a.(pagy.prev, '&lt;', aria_label: 'Previous') %>
      <% else %>
        <a role="link" aria-disabled="true" aria-label="Previous">&lt;</a>
      <% end %>
      <%# Page links (series example: [1, :gap, 7, 8, "9", 10, 11, :gap, 36]) %>
      <% pagy.series.each do |item| %>
        <% if item.is_a?(Integer) %>
            <%= a.(item) %>
        <% elsif item.is_a?(String) %>
          <a role="link" aria-disabled="true" aria-current="page" class="current"><%= item %></a>
        <% elsif item == :gap %>
          <a role="link" aria-disabled="true" class="gap">&hellip;</a>
        <% end %>
      <% end %>
      <%# Next page link %>
      <% if pagy.next %>
        <%= a.(pagy.next, '&gt;', aria_label: 'Next') %>
      <% else %>
        <a role="link" aria-disabled="true" aria-label="Next">&lt;</a>
    <% end %>
    </nav>
  ERB

  helpers do
    include Pagy::Frontend

    def style_menu
      html = +%(<div id="style-menu"> )
      STYLES.each_key { |style| html << %(<a href="/#{style}">#{style}</a>) }
      html << %(<a href="/template">template</a>)
      html << %(</div>)
    end

    def highlight(html, format: :html)
      if format == :html
        html = html.gsub(/>[\s]*</, '><').strip # template single line no spaces around/between tags
        html = Formatter.new.format(html)
      end
      lexer     = Rouge::Lexers::ERB.new
      formatter = Rouge::Formatters::HTMLInline.new('monokai.sublime')
      summary   = { html: 'Served HTML (pretty formatted)', erb: 'ERB Template' }
      %(<details><summary>#{summary[format]}</summary><pre>\n#{
         formatter.format(lexer.lex(html))
      }</pre></details>)
    end
  end
end

# Cheap pagy formatter for helpers output
class Formatter
  INDENT     = '  '
  TEXT_SPACE = "\u00B7"
  TEXT       = /^([^<>]+)(.*)/
  UNPAIRED   = /^(<(input|link).*?>)(.*)/
  PAIRED     = %r{^(<(head|nav|div|span|p|a|b|label|ul|li).*?>)(.*?)(</\2>)(.*)}
  WRAPPER    = /<.*?>/
  DATA_PAGY  = /(data-pagy="([^"]+)")/

  def initialize
    @formatted = +''
  end

  def format(input, level = 0)
    process(input, level)
    @formatted
  end

  private

  def process(input, level)
    push = ->(content) { @formatted << ((INDENT * level) << content << "\n") }
    rest = nil
    if (match = input.match(TEXT))
      text, rest = match.captures
      push.(text.gsub(' ', TEXT_SPACE))
    elsif (match = input.match(UNPAIRED))
      tag, _name, rest = match.captures
      push.(tag)
    elsif (match = input.match(PAIRED))
      tag_start, name, block, tag_end, rest = match.captures
      ## Handle incomplete same-tag nesting
      while block.scan(/<#{name}.*?>/).size > block.scan(tag_end).size
        more, rest = rest.split(tag_end, 2)
        block << tag_end << more
      end
      if (match = tag_start.match(DATA_PAGY))
        search, data = match.captures
        formatted = data.scan(/.{1,76}/).join("\n")
        replace = %(\n#{INDENT * (level + 1)}data-pagy="#{formatted}")
        tag_start.sub!(search, replace)
      end
      if block.match(WRAPPER)
        push.(tag_start)
        process(block, level + 1)
        push.(tag_end)
      else
        push.(tag_start << block << tag_end)
      end
    end
    process(rest, level) if rest
  end
end

# Simple array-based collection that acts as a standard DB collection.
class MockCollection < Array
  def initialize(arr = Array(1..1000))
    super
    @collection = clone
  end

  def offset(value)
    @collection = self[value..]
    self
  end

  def limit(value)
    @collection[0, value]
  end

  def count(*)
    size
  end
end

run PagyDemo

__END__

@@ layout
<!DOCTYPE html>
<html lang="en">
<head>
  <title>Pagy Demo App</title>
  <script src="<%= %(/javascripts/#{"pagy#{'-dev' if ENV['DEBUG']}.js"}) %>"></script>
  <script>
    window.addEventListener("load", Pagy.init);
  </script>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <%= erb :"#{style}_head" if defined?(style) %>
  <style type="text/css">
    @media screen { html, body {
      font-size: 1rem;
      line-heigth: 1.2s;
      padding: 0;
      margin: 0;
    } }
    body {
      background: white !important;
      margin: 0 !important;
      font-family: sans-serif !important;
    }
    h1, h4 {
      font-size: 1.8rem !important;
      font-weight: 600 !important;
      margin-top: 1rem !important;
      margin-bottom: 0.7rem !important;
      line-height: 1.5 !important;
      color: rgb(90 90 90)  !important;
    }
    h4 {
      font-family: monospace;
      font-size: .9rem !important;
      margin-top: 1.6rem !important;
    }
    summary, .notes {
      font-size: .8rem;
      color: gray;
      margin-top: .6rem;
      font-style: italic;
      cursor: pointer;
    }
    .notes {
      font-family: sans-serif;
      font-weight: normal;
    }
    .description {
       margin: 1rem 0;
    }
    .description a {
      color: blue;
      text-decoration: underline;
    }
    pre, pre code {
      display: block;
      margin-top: .3rem;
      margin-bottom: 1rem;
      font-size: .8rem !important;
      line-heigth: 1rem !important;
      color: white;
      background-color: rgb(30 30 30);
      padding: 1rem;
      overflow: auto;
    }
    .content {
      padding: 0 1.5rem 2rem !important;
    }

    #style-menu {
      flex;
      font-family: sans-serif;
      font-size: 1.1rem;
      line-height: 1.5rem;
      white-space: nowrap;
      color: white;
      background-color: gray;
      padding: .2rem 1.5rem;
    }
    #style-menu > :not([hidden]) ~ :not([hidden]) {
      --space-reverse: 0;
      margin-right: calc(0.5rem * var(--space-reverse));
      margin-left: calc(0.5rem * calc(1 - var(--space-reverse)));
    }
    #style-menu a {
      color: inherit;
      text-decoration: none;
    }
    /* Quick demo for overriding the element style attribute of certain pagy helpers
    .pagy input[style] {
      width: 5rem !important;
    }
    */
  </style>
</head>
<body>
  <!-- each different class used by each style -->
  <%= style_menu %>
  <div class="content">
    <%= yield %>
  </div>
</body>
</html>


@@ pagy_head
<!-- copy and paste the pagy style in order to edit it -->
<link rel="stylesheet" href="/stylesheets/pagy.css">

@@ bootstrap_head
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">

@@ bulma_head
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bulma@0.9.4/css/bulma.min.css">

@@ foundation_head
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/foundation-sites@6.8.1/dist/css/foundation.min.css" crossorigin="anonymous">

@@ materialize_head
<link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/materialize/1.0.0/css/materialize.min.css">

@@ semantic_head
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/semantic-ui@2.5.0/dist/semantic.min.css"><script
  src="https://code.jquery.com/jquery-3.1.1.min.js"
  integrity="sha256-hVVnYaiADRTO2PzUGmuLJr8BLUSjGIZsDYGmIJLv2b8="
  crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/semantic-ui@2.5.0/dist/semantic.min.js"></script>

@@ tailwind_head
<script src="https://cdn.tailwindcss.com?plugins=forms,typography,aspect-ratio"></script>
<!-- copy and paste the pagy.tailwind style in order to edit it -->
<style type="text/tailwindcss">
  <%= Pagy.root.join('stylesheets', 'pagy.tailwind.scss').read %>
</style>

@@ uikit_head
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/uikit@3.18.3/dist/css/uikit.min.css" />
<script src="https://cdn.jsdelivr.net/npm/uikit@3.18.3/dist/js/uikit.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/uikit@3.18.3/dist/js/uikit-icons.min.js"></script>


@@ helpers
<h1><%= style %></h1>
<% extra = STYLES[style][:extra] || "#{style}" %>
<p class="description">See the <a href="http://ddnexus.github.io/pagy/docs/extras/<%= extra %>"><%= extra %> extra</a>
documentation for details</p>

<h3>Collection</h3>
<p>@records: <%= @records.join(',') %></p>

<h4>pagy<%= prefix %>_nav</h4>
<%= html = send(:"pagy#{prefix}_nav", @pagy, id: 'nav', aria_label: 'Pages nav') %>
<%= highlight(html) %>

<h4>pagy<%= prefix %>_nav_js</h4>
<%= html = send(:"pagy#{prefix}_nav_js", @pagy, id: 'nav-js', aria_label: 'Pages nav_js') %>
<%= highlight(html) %>

<h4>pagy<%= prefix %>_nav_js <span class="notes">(responsive on window resize)</span></h4>
<%= html = send(:"pagy#{prefix}_nav_js", @pagy, id: 'nav-js-responsive',
     aria_label: 'Pages nav_js_responsive',
     steps: { 0 => 5, 500 => [1,3,3,1], 700 => [1,4,4,1], 900 => [2,4,4,2] }) %>
<%= highlight(html) %>

<h4>pagy<%= prefix %>_combo_nav_js</h4>
<%= html = send(:"pagy#{prefix}_combo_nav_js", @pagy, id: 'combo-nav-js', aria_label: 'Pages combo_nav_js') %>
<%= highlight(html) %>

<h4>pagy_info</h4>
<%= html = pagy_info(@pagy, id: 'pagy-info') %>
<%= highlight(html) %>

<% if style.match(/pagy|tailwind/) %>
<h4>pagy_items_selector_js</h4>
<%= html = pagy_items_selector_js(@pagy, id: 'items-selector-js') %>
<%= highlight(html) %>

<h4>pagy_prev_a / pagy_next_a</h4>
<%= html = '<nav class="pagy">' << pagy_prev_a(@pagy) << pagy_next_a(@pagy) << '</nav>' %>
<%= highlight(html) %>

<h4>pagy_prev_link / pagy_next_link <span class="notes">(link obviously not rendered)<span></h4>
<% html = '<head>' << (pagy_prev_link(@pagy)||'') << (pagy_next_link(@pagy)||'') << '</head>' %>
<%= highlight(html) %>
<% end %>


@@ template
<h1>Pagy Template Demo</h1>

<p class="description">
See the <a href="https://ddnexus.github.io/pagy/docs/how-to/#using-your-pagination-templates">
Custom Templates</a> documentation.
</p>
<h4>Collection</h4>
<p>@records: <%= @records.join(',') %></p>

<h4>Rendered ERB template</h4>

<%# We don't inline the template here, so we can highlight it more easily %>
<%= html = ERB.new(TEMPLATE).result(binding) %>
<%= highlight(TEMPLATE, format: :erb) %>
<%= highlight(html) %>
