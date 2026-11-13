package im.moonchat.biz.service.account.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.entity.AccountInfo;
import im.moonchat.biz.mapper.account.AccountInfoMapper;
import im.moonchat.biz.service.account.AccountKeyService;
import im.moonchat.biz.service.account.CredentialHasher;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AccountKeyServiceImpl implements AccountKeyService {

    private final AccountInfoMapper accountInfoMapper;
    private final CredentialHasher hasher;

    @Override
    public long authenticate(String plainKey) {
        AccountInfo info = accountInfoMapper.selectOne(new LambdaQueryWrapper<AccountInfo>()
                .eq(AccountInfo::getCredentialHash, hasher.hashAccountKey(plainKey)));
        if (info == null) {
            throw ApiException.unauthenticated();
        }
        return info.getAccountId();
    }
}
