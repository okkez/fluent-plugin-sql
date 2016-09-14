require "test/unit"
require "test/unit/rr"
require "test/unit/notify"
require "fluent/test"
require "fluent/test/helpers"
require "fluent/plugin/out_sql"
require "fluent/plugin/in_sql"

include Fluent::Test::Helpers

load "fixtures/schema.rb"
