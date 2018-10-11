def try_hard_to_remove_dir d

  begin
    `rm -rf #{d}`
  rescue => e
    $logger.error("Error cleaning up directory #{d}")
  end

  5.times {
    begin
      FileUtils.rm_rf(d)
      $logger.debug("Succeeded in cleaning up #{d}")
      return
    rescue => e
      $logger.error("Error cleaning up directory #{e}, sleeping and probably trying again")
      sleep(1)
    end
  }

  $logger.error("Failed in cleaning up directory #{e}")

end


def add_global_created_dir d
  $created_dirs << d
end
