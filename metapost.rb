# (The MIT License)
# Author: Imamochi momu

require 'digest'
require 'liquid'
require 'open3'

#relative to current directory

module Jekyll
  module Metapost
    class MetapostBlock < Liquid::Block
      include Liquid::StandardFilters
      #safe true
      #priority :low

      GRAPHVIZ_DIR = "images/metapost"
      DIV_CLASS_ATTR = "container"
      # The regular expression syntax checker. Start with the language specifier.
      # Follow that by zero or more space separated options that take one of two
      # forms:
      #
      # 1. name
      # 2. name=value
      SYNTAX = /^([a-zA-Z0-9.+#-]+)((\s+\w+(=\w+)?)*)$/

      def initialize(tag_name, markup, tokens)
        super
        puts("\n-> initialize "+markup)

        # set hash
        @time = Digest::MD5.hexdigest(Time.now.to_s)

        @layout = "unknown"
        @inline = true
        @link = false
        @mp_src = "#{@time}.mp"
        @mp_dest = "#{@time}.1"
        @tex_src = "#{@time}.tex"
        @dvi_src = "#{@time}.dvi"
        @pdf_src = "#{@time}.pdf"
        @opts = ""
        @class = ""
        @style = ""
        @graphviz_dir = File.absolute_path(GRAPHVIZ_DIR)

        @tex_template = <<-TEX
        \\documentclass[dvips]{jarticle}
        \\usepackage{graphicx}
        \\pagestyle{empty}
        \\begin{document}
        \\includegraphics{#{@mp_dest}}
        \\end{document}
        TEX

        #initialize options
        #        parse_options(@params,tag_name)

      end

      def read_config(name, site)
        cfg = site.config["xgraphviz"]
        return if cfg.nil?
        value = cfg[name]
      end


      def split_params(params)
        return params.split(" ").map(&:strip)
      end

      def parse_options(params,tag_name)
        if not(defined?(@format)) or @format.nil?
          @format = "svg"
        end

        if defined?(params) && not( params.nil?)
          if defined?(params) && params != ''
            puts("===> params -> "+params.to_s)
            options = split_params(params)

            options.each do |opt|
              key, value = opt.split('=')
              unless value.nil? or value.empty? then
                value = value.gsub(/[\\'\\"]/,"")
              end

              puts("===> option [#{key} = #{value}]")
              case key
              when 'svg' then
                @format = key

              when 'class' then
                @class = value

              when 'style' then
                @style = value

              when 'png' then
                @format = key
                @inline = false

              when 'format' then
                unless value.nil? or value.empty? then
                  @format = value
                end

              when 'opts' then
                unless value.nil? or value.empty? then
                  @opts = value
                end

              when 'url' then
                unless value.nil? or value.empty? then
                  @url = value
                  @link = true
                end

              when 'inline' then
                @inline=true
                unless value.nil? or value.empty? then
                  @inline = value == 'true'
                end

              else
                puts "unsupported option: #{key}"
              end

            end

            #end
          else
            raise SyntaxError.new <<-eos
            Syntax Error in tag #{tag_name} while parsing the following markup:

            #{params}

            Valid syntax: <xdot|xneato|xcirco|xtwopi> <png|svg> [param='value' param2='value']
            param='value': i.e(keep=<true|false> inline=<true|false> url=<filename> h=<height> w=<width> opts=<options>)

            eos
          end
        end

        if @format == 'png' then
          @inline = false
        end
      end


      def render(context)
        #initialize options
        site = context.registers[:site]
        value = read_config("destination", site)

        @graphviz_dir = value if !value.nil?

        puts("\n=> render")
        folder = File.join(site.source, GRAPHVIZ_DIR) #dest
        FileUtils.mkdir_p(folder)

        puts("\tfolder -> "+folder.to_s)
        puts("\tinline -> #{@inline}")
        puts("\tlink -> #{@link}")
        puts("\turl -> #{@url}")
        puts("\tlayout -> #{@layout}")
        puts("\tformat -> #{@format}")

        non_markdown = /(&amp|&lt|&nbsp|&quot|&gt|<\/p>|<\/h.>)/m

        # preprocess text
        code = super
        # get hash url
        @url = "#{Digest::MD5.hexdigest(code)}.svg"
        # write code file
        File.write(File.join(@graphviz_dir, @mp_src), code)
        # write tex File
        File.write(File.join(@graphviz_dir, @tex_src), @tex_template)
        svg = ""
        svg = generate_graph_from_content(context, code, folder, @mp_src)
        output = wrap_with_div(svg)

        output
        #output trigger last stdout is what gets display
      end

      def blank?
        false
      end

      def generate_graph_from_content(context, code, folder, inputfile)
        site = context.registers[:site]

        dot_cmd = "upmpost #{File.basename(inputfile)}"
        run_dot_cmd(dot_cmd, code)
        dot_cmd = "platex -kanji=utf8 #{@tex_src}"
        run_dot_cmd(dot_cmd, code)
        dot_cmd = "dvipdfmx -o #{@pdf_src} #{@dvi_src}"
        run_dot_cmd(dot_cmd, code)
        dot_cmd = "pdfcrop  #{@pdf_src} #{@pdf_src}"
        run_dot_cmd(dot_cmd, code)
        filename = "gen-" + File.basename(@url)
        output = File.join(@graphviz_dir, filename)
        puts("\n output =" + output)
        dot_cmd = "pdf2svg #{@pdf_src} #{File.basename(output)}"
        run_dot_cmd(dot_cmd, code)
        dot_cmd = "rm #{@graphviz_dir}/#{@time}.*"
        run_dot_cmd(dot_cmd, code)

        # Add the file to the list of static files for the final copy once generated
        st_file = Jekyll::StaticFile.new(site, site.source, GRAPHVIZ_DIR, filename)
        site.static_files << st_file

        if @style.empty? or @style.nil?
          @style = ""
        else
          @style = %[style="#{@style}"]
        end

        return "<img #{@style} src='#{File.join(GRAPHVIZ_DIR, filename)}'>"
      end

      def run_dot_cmd(dot_cmd,code)
        puts("\tdot_cmd -> "+dot_cmd)

        Open3.popen3( dot_cmd, :chdir => @graphviz_dir) do |stdin, stdout, stderr, wait_thr|
          stdin.print(code)
          stdin.close

          err = stderr.read
          #if not (err.nil? || err.strip.empty?)
          #  raise "Error from #{dot_cmd}:\n#{err}"
          #end

          svg = stdout.read

          svg.force_encoding('UTF-8')
          exit_status = wait_thr.value
          unless exit_status.success?
            abort "FAILED !!! #{dot_cmd}"
          end
          return svg
        end
      end


      def remove_declarations(svg)
        svg.sub(/<!DOCTYPE .+?>/im,'').sub(/<\?xml .+?\?>/im,'')
      end

      def remove_xmlns_attrs(svg)
        svg.sub(%[xmlns="http://www.w3.org/2000/svg"], '')
        .sub(%[xmlns:xlink="http://www.w3.org/1999/xlink"], '')
      end

      def wrap_with_div(svg)
        if @class.empty? or @class.nil?
          @class = ""
        else
          @class = %[class="#{@class}"]
        end

        if @style.empty? or @style.nil?
          @style = ""
        else
          @style = %[style="#{@style}"]
        end

        %[<div #{@class} #{@style} >#{svg}</div>]
      end

    end

  end
end

Liquid::Template.register_tag('metapost', Jekyll::Metapost::MetapostBlock)
