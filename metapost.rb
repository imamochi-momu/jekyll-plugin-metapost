# encoding: utf-8
#
# (The MIT License)
# Author: Imamochi momu

require 'digest'
require 'liquid'
require 'tmpdir'
require 'open3'

module Jekyll
  module Metapost
    class MetapostBlock < Liquid::Block
      include Liquid::StandardFilters
      # Default settings
      Defaults = {
        :output_dir => 'image/metapost',
        :div_class => 'container',
        :prefix => '',
        :debug => false,
        :increment => true,
      }.freeze

      # initialize
      def initialize(tag_name, markup, tokens)
        # call super class method
        super
        # parse
        parse_args(markup)
        # set hash
        @time = Digest::MD5.hexdigest(Time.now.to_s)

        @mp_src = "#{@time}.mp"
        @mp_dest = "#{@time}.1"
        @tex_src = "#{@time}.tex"
        @dvi_src = "#{@time}.dvi"
        @pdf_src = "#{@time}.pdf"

        @tex_template = <<-TEX
        \\documentclass[dvips]{jarticle}
        \\usepackage[dvipdfmx]{graphicx}
        \\usepackage{amsmath, euler}
        \\pagestyle{empty}
        \\begin{document}
        \\includegraphics{#{@mp_dest}}
        \\end{document}
        TEX
      end

      def parse_args(markup)
        args = markup.split(/(\w+=".*")|(\w+=.+)/).select {|s| !s.strip.empty?}
        p args
        args.each do |arg|
          arg.strip!
          if arg =~ /(\w+)="(.*)"/
            eval("@#{$1} = \'#{$2}\'")
            p "@1:#{$1} = #{$2}"
            next
          end
          if arg =~ /(\w+)=(.+)/
            eval("@#{$1} = \'#{$2}\'")
            p "@2:#{$1} = #{$2}"
            next
          end
        end
      end

      def render(context)
        site = context.registers[:site]
        # initialize options
        @options = Hash.new()
        @options.merge!(self.class::Defaults) { |_, option, _| option }
        unless site.config['metapost'].nil?
          @options.merge!(Jekyll::Utils.symbolize_hash_keys site.config['metapost']) { |_, _, option| option }
        end
        p @options if @options[:debug]
        # add exclude dir
        if site.config['exclude'].nil?
          site.config['exclude'] = Array.new(site.config['metapost'])
        else
          site.config['exclude'] << @options[:output_dir] unless site.config['exclude'].any? { |e| e == @options[:output_dir] }
        end
        folder = File.join(site.source, @options[:output_dir])
        FileUtils.mkdir_p(folder)
        # preprocess text
        code = super
        # generate filename
        @filename = @options[:prefix] + Digest::MD5.hexdigest(code) + '.svg'
        # write code file
        unless @options[:increment] && File.exist?(File.join(@options[:output_dir], @filename))
          Dir.mktmpdir('metapost'){|dir|
            File.write(File.join(dir, @mp_src), code)
            # write tex File
            File.write(File.join(dir, @tex_src), @tex_template)
            # generate files
            generate_metapost(context, dir, @mp_src)
          }
        end
        output = wrap_with_div(generate_img_tag(context))

        output
        #output trigger last stdout is what gets display
      end

      def generate_metapost(context, dir, inputfile)
        site = context.registers[:site]
        # output file
        output = File.join(File.absolute_path(@options[:output_dir]), @filename)
        # generate
        dot_cmd = "upmpost -tex=uplatex #{File.basename(inputfile)}"
        run_command(dot_cmd, dir)
        dot_cmd = "platex -kanji=utf8 #{@tex_src}"
        run_command(dot_cmd, dir)
        dot_cmd = "dvipdfmx -o #{@pdf_src} #{@dvi_src}"
        run_command(dot_cmd, dir)
        dot_cmd = "pdfcrop #{@pdf_src} #{@pdf_src}"
        run_command(dot_cmd, dir)
        if RUBY_PLATFORM.downcase =~ /mswin(?!ce)|mingw|cygwin|bccwin/
          dot_cmd = "gswin64 -o tmp.pdf -dNoOutputFonts -sDEVICE=pdfwrite #{@pdf_src}"
          run_command(dot_cmd, dir)
          dot_cmd = "pdf2svg tmp.pdf #{File.absolute_path(output)}"
          run_command(dot_cmd, dir)
        else
          dot_cmd = "pdf2svg #{@pdf_src} #{File.absolute_path(output)}"
          run_command(dot_cmd, dir)
        end

       puts("\n metapost output = " + output)
      end

      def generate_img_tag(context)
        site = context.registers[:site]
        # Add the file to the list of static files for the final copy once generated
        st_file = Jekyll::StaticFile.new(site, site.source, @options[:output_dir], @filename)
        site.static_files << st_file

        return "<img #{@style} src='/#{File.join(@options[:output_dir], @filename)}'>"
      end

      def run_command(dot_cmd, dir)
        puts("command -> " + dot_cmd) if @options[:debug]

        Open3.popen3( dot_cmd, :chdir => dir) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          exit_status = wait_thr.value
          unless exit_status.success?
            abort "FAILED !!! #{dot_cmd}"
          end
        end
      end

      def wrap_with_div(svg)
        if @class.nil? or @class.empty?
          classNames = %[class="metapost"]
        else
          classNames = %[class="metapost #{@class}"]
        end

        if @style.nil? or @style.empty?
          style = ""
        else
          style = %[style="#{@style}"]
        end

        if @caption.nil? or @caption.empty?
          caption = ""
        else
          caption = %[<figcaption>#{@caption}</figcaption>]
        end

        %[<figure #{classNames} #{style} ><div class="metapost">#{svg}</div>#{caption}</figure>]
      end

    end

  end
end

Liquid::Template.register_tag('metapost', Jekyll::Metapost::MetapostBlock)
