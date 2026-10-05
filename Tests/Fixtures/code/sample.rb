# Ruby sample fixture
class Greeting
  attr_reader :name

  def initialize(name = "PreviewX")
    @name = name
  end

  def salute
    puts "Hello, #{@name}!"
  end
end

Greeting.new.salute
