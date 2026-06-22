defmodule BookingTest do
  use ExUnit.Case
  doctest Booking

  test "greets the world" do
    assert Booking.hello() == :world
  end
end
