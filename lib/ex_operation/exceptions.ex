defmodule ExOperation.AssertionError do
  @moduledoc false

  defexception [:message]
end

defmodule ExOperation.StepError do
  @moduledoc false

  defexception [:operation, :txn, :name, :exception]

  def message(%{operation: operation, txn: txn, name: name, exception: exception}) do
    """
    Error in `#{inspect(operation.module)}` in step `#{inspect(name)}`:
    (#{exception.__struct__}) #{Exception.message(exception)}

    Current transaction state:
    #{inspect(txn)}

    Operation:
    #{inspect(operation)}
    """
  end
end

defmodule ExOperation.CallbackError do
  @moduledoc false

  defexception [:operation, :txn, :exception]

  def message(%{operation: operation, txn: txn, exception: exception}) do
    """
    Error in `#{inspect(operation.module)}` in callback:
    (#{exception.__struct__}) #{Exception.message(exception)}

    Current transaction state:
    #{inspect(txn)}

    Operation:
    #{inspect(operation)}
    """
  end
end

defmodule ExOperation.DeferError do
  @moduledoc false

  defexception [:operation, :txn, :exception]

  def message(%{operation: operation, txn: txn, exception: exception}) do
    """
    Error in `#{inspect(operation.module)}` in defer callback:
    (#{exception.__struct__}) #{Exception.message(exception)}

    Current transaction state:
    #{inspect(txn)}

    Operation:
    #{inspect(operation)}
    """
  end
end
