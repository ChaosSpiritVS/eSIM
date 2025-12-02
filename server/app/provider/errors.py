from __future__ import annotations
from typing import Optional


class ProviderError(Exception):
    def __init__(self, code: int, msg: str, http_status: int = 500):
        super().__init__(msg)
        self.code = code
        self.msg = msg
        self.http_status = http_status


def map_provider_code_to_http(code: int) -> int:
    # Example mappings based on earlier design notes
    mapping = {
        1003: 400,  # 参数错误
        1070: 404,  # 套餐不存在
        1081: 409,  # 重复交易
        1016: 401,  # 登录失败
        411: 401,   # 授权过期，需要刷新
    }
    return mapping.get(code, 502)


def raise_for_provider(code: int, msg: str):
    status = map_provider_code_to_http(code)
    raise ProviderError(code=code, msg=msg, http_status=status)