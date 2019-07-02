require_relative 'helper'

class TestParser < Minitest::Spec
  instance_eval &ParserSuite
  
  def create_parser(grammar)
    Glush::DirectParser.new(grammar)
  end
end

