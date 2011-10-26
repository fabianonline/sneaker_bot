class TwitterBot
    def respond_to(string, text)
        if Regexp.new("\\b#{string}\\b", true).match(text)
            yield
        end
    end
end
