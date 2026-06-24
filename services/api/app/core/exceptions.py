class RaasteException(Exception):
    def __init__(self, message: str, status_code: int = 400):
        self.message = message
        self.status_code = status_code
        super().__init__(self.message)


class NotFoundException(RaasteException):
    def __init__(self, message: str = "Resource not found"):
        super().__init__(message, status_code=404)


class ValidationException(RaasteException):
    def __init__(self, message: str = "Validation error"):
        super().__init__(message, status_code=422)


class UnauthorizedException(RaasteException):
    def __init__(self, message: str = "Unauthorized"):
        super().__init__(message, status_code=401)
