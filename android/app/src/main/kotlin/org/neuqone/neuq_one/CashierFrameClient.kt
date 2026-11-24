package org.neuqone.neuq_one

import android.graphics.Bitmap
import android.net.Uri
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient

// Android's Flutter delegate forwards main-frame navigations only. Some
// cashiers invoke the payment app through a hidden frame.
internal class CashierFrameClient(
    private val delegate: WebViewClient,
    private val openWallet: (page: Uri, target: Uri) -> Boolean
) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        val page = view.url
        if (!request.isForMainFrame && page != null && openWallet(Uri.parse(page), request.url)) {
            return true
        }
        return delegate.shouldOverrideUrlLoading(view, request)
    }

    override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) =
        delegate.onPageStarted(view, url, favicon)

    override fun onPageFinished(view: WebView, url: String) =
        delegate.onPageFinished(view, url)

    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) =
        delegate.onReceivedError(view, request, error)

    override fun onReceivedHttpError(
        view: WebView,
        request: WebResourceRequest,
        response: WebResourceResponse
    ) = delegate.onReceivedHttpError(view, request, response)

    override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) =
        delegate.doUpdateVisitedHistory(view, url, isReload)
}
