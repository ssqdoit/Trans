function translate(request) {
  return {
    text: "[" + request.to + "] " + request.text,
    detectedLanguage: request.from
  };
}
