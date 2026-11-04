package im.moonchat.biz.web;

import com.fasterxml.jackson.annotation.JsonInclude;

/** 失败响应体：{ "code": ..., "message": ..., "field": ... }，field 只在 validation_failed 时出现。 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ErrorResponse(String code, String message, String field) {
}
