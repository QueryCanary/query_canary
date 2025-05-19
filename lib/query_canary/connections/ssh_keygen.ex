defmodule QueryCanary.Connections.SSHKeygen do
  @moduledoc """
  Generates an SSH keypair (ED25519 only).

  Was ed25519 now secp256r1 ??
  """

  def generate_keypair(comment) do
    with {_, _, _, params, public, _} = private <-
           :public_key.generate_key({:namedCurve, :secp256r1}),
         entry <- :public_key.pem_entry_encode(:ECPrivateKey, private),
         pem_private <- :public_key.pem_encode([entry]),
         ssh_public <-
           :ssh_file.encode([{{{:ECPoint, public}, params}, [{:comment, comment}]}], :openssh_key),
         do: {:ok, pem_private, ssh_public}
  end
end
