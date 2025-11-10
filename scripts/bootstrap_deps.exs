Mix.install([])

{lock, _} = File.read!("mix.lock") |> Code.eval_string()
base_tmp = Path.join("tmp", "hex-downloads")
File.mkdir_p!(base_tmp)
File.mkdir_p!("deps")

Enum.each(lock, fn {app_atom, {:hex, pkg_atom, version, _checksum, _managers, _deps, _repo, _}} ->
  app = Atom.to_string(app_atom)
  pkg = Atom.to_string(pkg_atom)
  dep_dir = Path.join("deps", app)

  if File.dir?(dep_dir) do
    IO.puts("Skipping #{app}, already present")
  else
    tar_name = "#{pkg}-#{version}.tar"
    tar_path = Path.join(base_tmp, tar_name)
    url = "https://repo.hex.pm/tarballs/#{tar_name}"

    IO.puts("Downloading #{url}")
    {_, status} = System.cmd("curl", ["-fSL", url, "-o", tar_path])
    if status != 0 do
      raise "curl failed for #{url}"
    end

    unpack_dir = Path.join(base_tmp, "unpacked_#{app}")
    File.rm_rf!(unpack_dir)
    File.mkdir_p!(unpack_dir)

    {_, status2} = System.cmd("tar", ["-xf", tar_path, "-C", unpack_dir])
    if status2 != 0 do
      raise "tar extract failed for #{tar_path}"
    end

    contents_tar = Path.join(unpack_dir, "contents.tar.gz")
    File.mkdir_p!(dep_dir)
    {_, status3} = System.cmd("tar", ["-xzf", contents_tar, "-C", dep_dir])
    if status3 != 0 do
      raise "tar contents extract failed for #{contents_tar}"
    end

    metadata = Path.join(unpack_dir, "metadata.config")
    if File.exists?(metadata) do
      File.cp!(metadata, Path.join(dep_dir, "hex_metadata.config"))
    end
  end
end)
