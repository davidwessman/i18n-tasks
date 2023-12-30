# frozen_string_literal: true

require 'i18n/tasks/scanners/ruby_ast_scanner'
require 'i18n/tasks/scanners/local_ruby_parser'
require "syntax_tree/erb"
require "pry"

module I18n::Tasks::Scanners
  # Scan for I18n.translate calls in ERB-file better-html and ASTs
  class ErbAstScanner < RubyAstScanner
    DEFAULT_REGEXP = /<%(={1,2}|-|\#|%)?(.*?)([-=])?%>/m.freeze

    def initialize(**args)
      super(**args)
      @ruby_parser = LocalRubyParser.new(ignore_blocks: true)
    end

    private

    # Parse file on path and returns AST and comments.
    #
    # @param path Path to file to parse
    # @return [{Parser::AST::Node}, [Parser::Source::Comment]]
    def path_to_ast_and_comments(path)
      source = SyntaxTree::ERB.read(path)
      syntax_tree = SyntaxTree::ERB.parse(source)

      methods = %w[t t! translate translate!]
      nodes = [SyntaxTree::ERB::ErbComment, SyntaxTree::CallNode]
      st_nodes = [SyntaxTree::Node, SyntaxTree::Program, SyntaxTree::Statements]
      queue = [syntax_tree]
      node_types = Set.new([])

      results = []

      while (node = queue.shift)
        node_types.add(node.class)

        if node.is_a?(SyntaxTree::ERB::ErbNode)
          queue.concat(node.content.value.child_nodes)
        else
          queue.concat(node.child_nodes)
        end

        next unless nodes.include?(node.class)
        binding.pry

        next unless methods.include?(node.message.value)

        # CallNode
        arguments =
          node.arguments.arguments.parts.map { |part| extract_value(part) }

        results << {
          method: node.message.value,
          key: arguments[0],
          options: arguments[1],
          location: node.location.deconstruct_keys("")
        }
      end

      binding.pry
      results

      # parser = BetterHtml::Parser.new(make_buffer(path))
      # ast = convert_better_html(parser.ast)
      # @erb_ast_processor.process_and_extract_comments(ast)
    end

    # Convert BetterHtml nodes to Parser::AST::Node
    #
    # @param node BetterHtml::Parser::AST::Node
    # @return Parser::AST::Node
    def convert_better_html(node)
      definition =
        Parser::Source::Map::Definition.new(
          node.location.begin,
          node.location.begin,
          node.location.begin,
          node.location.end
        )
      Parser::AST::Node.new(
        node.type,
        node.children.map do |child|
          if child.is_a?(BetterHtml::AST::Node)
            convert_better_html(child)
          else
            child
          end
        end,
        { location: definition }
      )
    end

    def extract_value(node)
      return if node.nil?

      if [
           SyntaxTree::StringLiteral,
           SyntaxTree::DynaSymbol,
           SyntaxTree::ArrayLiteral
         ].include?(node.class)
        node.child_nodes.map { |child_node| extract_value(child_node) }.join
      elsif [
            SyntaxTree::SymbolLiteral,
            SyntaxTree::Ident,
            SyntaxTree::TStringContent
          ].include?(node.class)
        extract_value(node.value)
      elsif node.is_a?(SyntaxTree::Label)
        node.value.gsub(/:/, "")
      elsif node.is_a?(SyntaxTree::BareAssocHash)
        result = {}
        node.assocs.each do |assoc|
          result[extract_value(assoc.key)] = extract_value(assoc.value)
        end
        result
      else
        binding.pry unless node.is_a?(String)
        node
      end
    end
  end
end
