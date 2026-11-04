package im.moonchat.biz.common;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** 把领域异常与入口校验失败收敛成 docs/api-contracts.md §1.3 的固定失败体。 */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    ResponseEntity<ErrorResponse> handle(ApiException e) {
        return ResponseEntity.status(e.status())
                .body(new ErrorResponse(e.code(), e.getMessage(), e.field()));
    }

    /** 入口校验只在这里做一次，之后靠类型系统流转。 */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorResponse> handleInvalidBody(MethodArgumentNotValidException e) {
        FieldError error = e.getBindingResult().getFieldError();
        String field = error == null ? null : wireName(error.getField());
        String message = error == null ? "请求体不合法" : error.getDefaultMessage();
        return handle(ApiException.validationFailed(field, message));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<ErrorResponse> handleUnreadableBody(HttpMessageNotReadableException e) {
        return handle(ApiException.validationFailed(null, "请求体不是合法的 JSON"));
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorResponse> handleUnexpected(Exception e) {
        log.error("未分类的服务端错误", e);
        return ResponseEntity.internalServerError().body(new ErrorResponse("internal_error", "服务端错误", null));
    }

    /** 响应字段是 snake_case（§1.4），校验报错也要指回客户端看得到的那个名字。 */
    private static String wireName(String field) {
        return field.replaceAll("([A-Z])", "_$1").toLowerCase();
    }
}
