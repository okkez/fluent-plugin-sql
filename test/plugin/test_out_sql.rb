require "helper"

class SqlOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  def teardown
  end

  CONFIG = %[
    host localhost
    port 5432
    adapter postgresql

    database fluentd_test
    username fluentd
    password fluentd

    remove_tag_prefix db

    <table>
      table logs
      column_mapping timestamp:created_at,host:host,ident:ident,pid:pid,message:message
    </table>
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::SQLOutput).configure(conf)
  end

  def test_configure
    d = create_driver
    expected = {
      host: "localhost",
      port: 5432,
      adapter: "postgresql",
      database: "fluentd_test",
      username: "fluentd",
      password: "fluentd",
      remove_tag_suffix: /^db/,
      enable_fallback: true
    }
    actual = {
      host: d.instance.host,
      port: d.instance.port,
      adapter: d.instance.adapter,
      database: d.instance.database,
      username: d.instance.username,
      password: d.instance.password,
      remove_tag_suffix: d.instance.remove_tag_prefix,
      enable_fallback: d.instance.enable_fallback
    }
    assert_equal(expected, actual)
    assert_empty(d.instance.tables)
    default_table = d.instance.instance_variable_get(:@default_table)
    assert_equal("logs", default_table.table)
  end

  def test_emit
    d = create_driver
    time = Time.parse("2011-01-02 13:14:15 UTC").to_i

    d.emit({"message" => "message1"}, time)
    d.emit({"message" => "message2"}, time)

    d.run

    default_table = d.instance.instance_variable_get(:@default_table)
    model = default_table.instance_variable_get(:@model)
    assert_equal(2, model.all.count)
    messages = model.pluck(:message).sort
    assert_equal(["message1", "message2"], messages)
  end

  class Fallback < self
    def test_simple
      d = create_driver
      time = Time.parse("2011-01-02 13:14:15 UTC").to_i

      d.emit({"message" => "message1"}, time)
      d.emit({"message" => "message2"}, time)

      d.run do
        default_table = d.instance.instance_variable_get(:@default_table)
        model = default_table.instance_variable_get(:@model)
        mock(model).import(anything).at_least(1) do
          raise ActiveRecord::Import::MissingColumnError.new("dummy_table", "dummy_column")
        end
        mock(default_table).one_by_one_import(anything)
      end
    end

    def test_limit
      d = create_driver
      time = Time.parse("2011-01-02 13:14:15 UTC").to_i

      d.emit({"message" => "message1"}, time)
      d.emit({"message" => "message2"}, time)

      d.run do
        default_table = d.instance.instance_variable_get(:@default_table)
        model = default_table.instance_variable_get(:@model)
        mock(model).import([anything, anything]).once do
          raise ActiveRecord::Import::MissingColumnError.new("dummy_table", "dummy_column")
        end
        mock(model).import([anything]).times(12) do
          raise StandardError
        end
        assert_equal(5, default_table.instance_variable_get(:@num_retries))
      end
    end
  end

  class WithdrawingLabel < self
    def test_default
      conf = CONFIG + %[
               discard_error_records false
             ]
      d = create_driver(conf)

      time = Time.parse("2011-01-02 13:14:15 UTC").to_i

      d.emit({"message" => "message1"}, time)
      d.emit({"message" => "message2"}, time)

      d.run do
        default_table = d.instance.instance_variable_get(:@default_table)
        model = default_table.instance_variable_get(:@model)
        mock(model).import([anything, anything]).once do
          raise ActiveRecord::Import::MissingColumnError.new("dummy_table", "dummy_column")
        end
        mock(model).import([anything]).times(12) do
          raise StandardError
        end
        dummy_label = Object.new
        dummy_router = Object.new
        mock(dummy_router).emit_stream("test", anything)
        mock(dummy_label).event_router { dummy_router }

        mock(Fluent::Engine.root_agent).find_label("@OUT_SQL_WITHDRAW") { dummy_label }
      end
    end
  end
end
