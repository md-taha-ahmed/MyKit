package eu.kanade.tachiyomi.util

import rx.Observable
import tachiyomi.core.common.util.lang.awaitSingle as awaitSingleImpl

suspend fun <T> Observable<T>.awaitSingle(): T = awaitSingleImpl()
