# frozen_string_literal: true

class DecentCIKnownError < StandardError
end

class CannotMatchCompiler < DecentCIKnownError
end

class NoDecentCIFiles < DecentCIKnownError
end
