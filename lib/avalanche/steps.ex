defmodule Avalanche.Steps do
  @moduledoc """
  A collection of custom steps.
  """

  require Logger

  @unix_epoch ~D[1970-01-01]

  ## Request steps

  ## Response steps

  @doc """
  Decodes response `body.data` based on the `resultSetMetaData`.

  https://docs.snowflake.com/en/developer-guide/sql-api/reference.html#label-sql-api-reference-resultset-resultsetmetadata
  """
  def decode_body_data(request_response)

  def decode_body_data({request, %{body: ""} = response}) do
    {request, response}
  end

  # TODO: handle multiple partitions
  # "numRows" => 2,
  # "partitionInfo" => [%{"rowCount" => 2, "uncompressedSize" => 82}],
  def decode_body_data({request, %{status: 200, body: body} = response}) do
    metadata = Map.fetch!(body, "resultSetMetaData")
    row_types = Map.fetch!(metadata, "rowType")
    data = Map.fetch!(body, "data")

    decoded_data = _decode_body_data(row_types, data)

    {request, %Req.Response{response | body: Map.put(body, "data", decoded_data)}}
  end

  def decode_body_data(request_response), do: request_response

  defp _decode_body_data(types, data) do
    Enum.map(data, fn row ->
      Enum.zip_reduce(types, row, %{}, fn type, value, result ->
        key = Map.fetch!(type, "name")
        value = decode(type, value)
        Map.put(result, key, value)
      end)
    end)
  end

  defp decode(_type, value) when is_nil(value), do: nil

  defp decode(%{"type" => "fixed" = type}, value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> return_raw(type, value, :integer_parse_error)
    end
  end

  defp decode(%{"type" => "float" = type}, value) do
    case Float.parse(value) do
      {float, _rest} -> float
      :error -> return_raw(type, value, :float_parse_error)
    end
  end

  defp decode(%{"type" => "real" = type}, value) do
    case Float.parse(value) do
      {float, _rest} -> float
      :error -> return_raw(type, value, :float_parse_error)
    end
  end

  defp decode(%{"type" => "text"}, value), do: value

  defp decode(%{"type" => "boolean"}, value), do: value == "true"

  # Integer value (in a string) of the number of days since the epoch (e.g. 18262).
  defp decode(%{"type" => "date" = type}, value) do
    case Integer.parse(value) do
      {days, _rest} -> Date.add(@unix_epoch, days)
      :error -> return_raw(type, value, :integer_parse_error)
    end
  end

  # Float value (with 9 decimal places) of the number of seconds since the epoch (e.g. 82919.000000000).
  defp decode(%{"type" => "time" = type}, value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> time
      {:error, error} -> return_raw(type, value, error)
    end
  end

  defp decode(%{"type" => "timestamp_ltz" = type}, value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _utc_offset} -> datetime
      {:error, error} -> return_raw(type, value, error)
    end
  end

  defp decode(%{"type" => "timestamp_ntz" = type}, value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      {:error, error} -> return_raw(type, value, error)
    end
  end

  defp decode(%{"type" => "timestamp_tz" = type}, value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _utc_offset} -> datetime
      {:error, error} -> return_raw(type, value, error)
    end
  end

  defp decode(%{"type" => "object" = type}, value) do
    case Jason.decode(value) do
      {:ok, json} -> json
      {:error, error} -> return_raw(type, value, error)
    end
  end

  # maybe json, maybe something else
  defp decode(%{"type" => "variant" = type}, value) do
    case Jason.decode(value) do
      {:ok, json} -> json
      {:error, error} -> return_raw(type, value, error)
    end
  end

  defp decode(%{"type" => "array" = type}, value) do
    case Jason.decode(value) do
      {:ok, json} -> json
      {:error, error} -> return_raw(type, value, error)
    end
  end

  defp decode(%{"type" => type}, value) do
    Logger.error("Failed decode of unsupported type: #{type}")
    value
  end

  defp return_raw(type, value, error) do
    Logger.error("Failed decode of '#{type}' value: #{error}")
    value
  end
end
