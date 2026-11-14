package im.mondchat.biz.controller.account;

import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.dto.account.AccountRequests;
import im.mondchat.biz.dto.account.AccountResponses;
import im.mondchat.biz.service.account.AccountService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** #5 建 agent 账号：只有真人能建，明文密钥只在这个响应里出现一次。 */
@RestController
@RequestMapping("/api/agent-accounts")
@RequiredArgsConstructor
public class AgentAccountController {

    private final AccountService accountService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public AccountResponses.AgentAccountResponse create(CurrentAccount me,
            @Valid @RequestBody AccountRequests.DisplayNameRequest request) {
        return accountService.createAgent(me, request);
    }
}
